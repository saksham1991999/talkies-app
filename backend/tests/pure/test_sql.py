"""The migrations and the SQL inside the routers, checked without a database.

pglast (the Postgres parser) reads every migration and every SQL string of the
app. The checks below cannot run the SQL, so they look for the mistakes that
are easy to make by hand: a wrong column or table name, a missing parameter,
RLS left off, a non-owner query that touches `data`.
"""

import ast
import re
from dataclasses import dataclass, field
from pathlib import Path

import pytest
from pglast import enums, parse_sql
from pglast.ast import (
    AlterDefaultPrivilegesStmt,
    AlterTableStmt,
    ColumnDef,
    Constraint,
    CreateFunctionStmt,
    CreatePolicyStmt,
    CreateStmt,
    CreateTrigStmt,
    GrantStmt,
    ViewStmt,
)
from pglast.parser import parse_plpgsql_json
from pglast.visitors import Visitor

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = sorted((ROOT / "supabase" / "migrations").glob("*.sql"))
APP = ROOT / "backend" / "app"

# Modules that may read and write the owner's tables (`stubs`, `wishes`, `user_docs`).
OWNER_MODULES = {"routers/sync.py", "routers/wrapup.py"}
# Modules that answer another person: no diary timestamp, ever.
FRIEND_MODULES = {"routers/friends.py", "routers/users.py", "routers/feed.py"}

# Foreign keys that do not cascade, and why.
NOT_CASCADE = {
    ("groups", "owner_id", "profiles", "r"),  # the hand_over_groups trigger runs first
    ("nights", "host_id", "profiles", "n"),  # the night stays, the host becomes null
    ("messages", "night_id", "nights", "n"),  # the message stays, the link becomes null
}


@dataclass
class Schema:
    tables: dict[str, list[str]] = field(default_factory=dict)
    views: dict[str, list[str]] = field(default_factory=dict)
    fks: list[tuple[str, str, str, str]] = field(default_factory=list)  # table, column, ref, action
    created_in: dict[str, int] = field(default_factory=dict)  # table or view -> migration index

    def columns(self, relation: str) -> list[str]:
        return self.tables.get(relation) or self.views.get(relation) or []

    def known(self, relation: str) -> bool:
        return relation in self.tables or relation in self.views or relation == "users"


def _relname(node) -> str:
    return node.relname


def _view_columns(query) -> list[str]:
    select = query
    while getattr(select, "larg", None) is not None:  # a union: the first branch names the columns
        select = select.larg
    names = []
    for target in select.targetList:
        if target.name:
            names.append(target.name)
        else:
            names.append(target.val.fields[-1].sval)
    return names


def load_schema() -> Schema:
    schema = Schema()
    for index, path in enumerate(MIGRATIONS):
        for raw in parse_sql(path.read_text()):
            stmt = raw.stmt
            if isinstance(stmt, CreateStmt):
                table = _relname(stmt.relation)
                columns = []
                for element in stmt.tableElts:
                    if isinstance(element, ColumnDef):
                        columns.append(element.colname)
                        for con in element.constraints or ():
                            if con.contype == enums.ConstrType.CONSTR_FOREIGN:
                                schema.fks.append(
                                    (
                                        table,
                                        element.colname,
                                        _relname(con.pktable),
                                        con.fk_del_action,
                                    )
                                )
                    elif (
                        isinstance(element, Constraint)
                        and element.contype == enums.ConstrType.CONSTR_FOREIGN
                    ):
                        for attr in element.fk_attrs:
                            target = _relname(element.pktable)
                            schema.fks.append((table, attr.sval, target, element.fk_del_action))
                schema.tables[table] = columns
                schema.created_in[table] = index
            elif isinstance(stmt, ViewStmt):
                view = _relname(stmt.view)
                schema.views[view] = _view_columns(stmt.query)
                schema.created_in[view] = index
    return schema


SCHEMA = load_schema()


# --- the migrations ---------------------------------------------------------


def test_migration_files_are_named_one_to_five():
    names = [p.name for p in MIGRATIONS]
    assert len(names) == 5
    for n, name in enumerate(names, start=1):
        assert re.fullmatch(rf"2026100100000{n}_phase{n}_[a-z_]+\.sql", name), name


@pytest.mark.parametrize("path", MIGRATIONS, ids=lambda p: p.name)
def test_migration_parses_including_function_bodies(path: Path):
    text = path.read_text()
    statements = parse_sql(text)
    assert statements
    for raw in statements:
        if isinstance(raw.stmt, CreateFunctionStmt):
            options = {o.defname: o.arg for o in raw.stmt.options}
            if options["language"].sval == "plpgsql":
                parse_plpgsql_json(text[raw.stmt_location : raw.stmt_location + raw.stmt_len])


@pytest.mark.parametrize("path", MIGRATIONS, ids=lambda p: p.name)
def test_header_footer_rls_and_no_policy(path: Path):
    text = path.read_text()
    assert chr(0x2014) not in text
    created, rls, revoked = set(), set(), set()
    default_privileges = []
    for raw in parse_sql(text):
        stmt = raw.stmt
        assert not isinstance(stmt, CreatePolicyStmt), "no policies: the backend is the only reader"
        if isinstance(stmt, CreateStmt):
            created.add(_relname(stmt.relation))
        elif isinstance(stmt, ViewStmt):
            created.add(_relname(stmt.view))
        elif isinstance(stmt, AlterTableStmt):
            for cmd in stmt.cmds:
                if cmd.subtype == enums.AlterTableType.AT_EnableRowSecurity:
                    rls.add(_relname(stmt.relation))
        elif isinstance(stmt, AlterDefaultPrivilegesStmt):
            default_privileges.append(stmt)
        elif (
            isinstance(stmt, GrantStmt)
            and not stmt.is_grant
            and stmt.objtype == enums.ObjectType.OBJECT_TABLE
        ):
            grantees = {g.rolename for g in stmt.grantees if g.rolename}
            if {"anon", "authenticated"} <= grantees:
                revoked |= {_relname(o) for o in stmt.objects}
    tables = {t for t in created if t in SCHEMA.tables}
    assert tables, "a migration without tables"
    assert tables == rls, f"RLS missing on {tables - rls}"
    assert created <= revoked, f"revoke from anon, authenticated missing on {created - revoked}"
    assert len(default_privileges) == 4  # tables, sequences, functions, and execute from public
    assert all(not s.action.is_grant for s in default_privileges)
    assert text.index("alter default privileges") < text.index("create ")
    assert "enable row level security" in text.rsplit("-- Footer", 1)[1]


def test_security_definer_is_never_used():
    for path in MIGRATIONS:
        assert "security definer" not in path.read_text().lower()


def test_foreign_keys_cascade_from_profiles():
    for table, column, ref, action in SCHEMA.fks:
        if (table, column, ref, action) in NOT_CASCADE:
            continue
        assert action == "c", (table, column, ref, action)
    assert {fk for fk in SCHEMA.fks if fk[3] != "c"} == NOT_CASCADE


def test_every_table_reaches_profiles():
    graph: dict[str, set[str]] = {}
    for table, _, ref, _ in SCHEMA.fks:
        graph.setdefault(table, set()).add(ref)
    # reports_archive holds no user id on purpose: the moderation trail survives
    # the deleted account (see the phase 2 migration).
    survive = {"profiles", "reports_archive"}
    for table in SCHEMA.tables:
        if table in survive:
            continue
        seen, todo = set(), [table]
        while todo:
            node = todo.pop()
            if node in seen:
                continue
            seen.add(node)
            todo.extend(graph.get(node, ()))
        assert "profiles" in seen, f"{table} would survive a deleted account"


def test_profiles_hands_over_groups_before_the_delete():
    text = (MIGRATIONS[2]).read_text()
    triggers = [r.stmt for r in parse_sql(text) if isinstance(r.stmt, CreateTrigStmt)]
    assert [(_relname(t.relation), t.timing, t.row) for t in triggers] == [("profiles", 2, True)]
    assert triggers[0].events == 8  # delete
    assert "on delete restrict" in text


def test_tables_only_point_at_earlier_tables():
    for table, _, ref, _ in SCHEMA.fks:
        if ref == "users":
            continue
        assert SCHEMA.created_in[ref] <= SCHEMA.created_in[table], (table, ref)
    for path in MIGRATIONS:
        index = MIGRATIONS.index(path)
        for raw in parse_sql(path.read_text()):
            if isinstance(raw.stmt, ViewStmt):
                sources = _Collect()
                sources(raw.stmt.query)
                for relation in sources.relations:
                    assert SCHEMA.known(relation), relation
                    assert SCHEMA.created_in.get(relation, -1) <= index


def test_views_hide_data_and_timestamps():
    assert {"v_audience", "v_visible_stubs", "v_visible_wishes", "v_my_stubs"} <= set(SCHEMA.views)
    for name, columns in SCHEMA.views.items():
        assert "data" not in columns, name
        for column in columns:
            assert not re.search(r"(_at|_on|created|updated|deleted|watched)", column), (
                name,
                column,
            )
    for raw_path in MIGRATIONS:
        for raw in parse_sql(raw_path.read_text()):
            if isinstance(raw.stmt, ViewStmt):
                options = {o.defname: o.arg.sval for o in raw.stmt.options}
                assert options.get("security_invoker") == "true", raw.stmt.view.relname


def test_friend_views_stay_inside_the_rules():
    text = "\n".join(p.read_text() for p in MIGRATIONS)
    stubs = text[text.index("create view v_visible_stubs") :]
    stubs = stubs[: stubs.index(";")]
    for needle in (
        "not t.private",
        "t.deleted_at is null",
        "'^Q[0-9]{1,12}$'",
        "case when p.share_ratings",
    ):
        assert needle in stubs, needle
    audience = text[text.index("create view v_audience") :]
    audience = audience[: audience.index(";")]
    for needle in ("p.visibility = 'friends'", "not blocked_either"):
        assert needle in audience, needle


def test_feed_freshness_is_rechecked_on_read_and_matches_the_backend_constant():
    from app.logic.validate import FEED_FRESH_DAYS

    text = "\n".join(p.read_text() for p in MIGRATIONS)
    stubs = text[text.index("create view v_visible_stubs") :]
    stubs = stubs[: stubs.index(";")]
    # A stub that was fresh at push time loses its feed_seq here once it is too
    # old, so old entries un-share from the feed without a new push.
    assert f"current_date - {FEED_FRESH_DAYS}" in stubs, stubs


# --- the SQL in the app -----------------------------------------------------

_SQL_START = re.compile(
    r"^\s*(with\s+\w+\s+as\s*\(|select\s|insert\s+into\s|update\s+\w+\s+set\s|delete\s+from\s)",
    re.I,
)


def python_files() -> list[Path]:
    return sorted(p for p in APP.rglob("*.py") if p.name != "__init__.py")


def relative(path: Path) -> str:
    return str(path.relative_to(APP))


def sql_strings(path: Path) -> list[tuple[str, int]]:
    """(text, line) of each string constant in a module that is a SQL statement."""
    tree = ast.parse(path.read_text())
    found = []
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Constant)
            and isinstance(node.value, str)
            and _SQL_START.match(node.value)
        ):
            found.append((node.value, node.lineno))
    return found


ALL_SQL = [(p, text, line) for p in python_files() for text, line in sql_strings(p)]
IDS = [f"{relative(p)}:{line}" for p, _, line in ALL_SQL]


def test_there_is_sql_to_check():
    assert len(ALL_SQL) > 100


def test_sql_is_never_built_with_f_strings_or_formatting():
    keywords = re.compile(r"\b(select|insert\s+into|delete\s+from)\b|\bupdate\s+\w+\s+set\b", re.I)
    for path in python_files():
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.JoinedStr):
                parts = "".join(v.value for v in node.values if isinstance(v, ast.Constant))
                if relative(path) != "routers/invite.py":
                    assert not keywords.search(parts), f"{relative(path)}:{node.lineno} builds SQL"
            formatted = (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "format"
                and isinstance(node.func.value, ast.Constant)
            )
            if formatted:
                assert not keywords.search(str(node.func.value.value)), relative(path)


@pytest.mark.parametrize("path, text, line", ALL_SQL, ids=IDS)
def test_every_sql_string_parses(path, text, line):
    parse_sql(text)


def test_non_owner_sql_never_reads_data_or_the_owner_tables():
    owner_table = re.compile(
        r"\b(from|join|into|update)\s+(public\.)?(stubs|wishes|user_docs)\b", re.I
    )
    data_column = re.compile(r"\bdata\b", re.I)
    checked = 0
    for path, text, line in ALL_SQL:
        if relative(path) in OWNER_MODULES:
            continue
        checked += 1
        where = f"{relative(path)}:{line}"
        assert not owner_table.search(text), f"{where} reads an owner table"
        assert not data_column.search(text), f"{where} reads a data column"
    assert checked > 80


def test_friend_facing_sql_reads_no_diary_timestamp():
    stamps = re.compile(r"\b(created_at|updated_at|deleted_at|watched_on|joined_at)\b", re.I)
    seen = 0
    for path, text, line in ALL_SQL:
        if relative(path) in FRIEND_MODULES:
            seen += 1
            assert not stamps.search(text), f"{relative(path)}:{line}"
    assert seen > 10


def test_views_are_always_asked_the_right_question():
    for path, text, line in ALL_SQL:
        where = f"{relative(path)}:{line}"
        if re.search(r"\bv_my_stubs\b", text):
            assert re.search(r"\buser_id = \$[12]\b", text), (
                f"{where}: v_my_stubs needs the caller's id"
            )
        if re.search(r"\b(v_visible_stubs|v_visible_wishes|v_audience)\b", text):
            assert re.search(r"\bviewer_id = \$[12]\b", text), f"{where}: ask as the viewer"
        for column in ("recency", "ord"):
            for hit in re.finditer(rf"\b{column}\b", text):
                before = text[: hit.start()].split("\n")[-1]
                ordering = re.search(r"(order by [^()]*|min\()$", before)
                assert ordering, f"{where}: {column} is only for ordering"


def test_parameters_are_numbered_without_gaps():
    for path, text, line in ALL_SQL:
        numbers = {int(n) for n in re.findall(r"\$(\d+)", text)}
        if numbers:
            assert numbers == set(range(1, max(numbers) + 1)), f"{relative(path)}:{line}"


def test_calls_pass_as_many_arguments_as_the_sql_has_parameters():
    """For `c.fetch(SQL, a, b)` where SQL is a name or a string: count the arguments."""
    checked = 0
    for path in python_files():
        tree = ast.parse(path.read_text())
        constants = {
            target.id: node.value.value
            for node in tree.body
            if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant)
            for target in node.targets
            if isinstance(target, ast.Name) and isinstance(node.value.value, str)
        }
        for node in ast.walk(tree):
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)):
                continue
            if node.func.attr not in {"fetch", "fetchrow", "fetchval", "execute"} or not node.args:
                continue
            first = node.args[0]
            if isinstance(first, ast.Name):
                sql = constants.get(first.id)
            elif isinstance(first, ast.Constant):
                sql = first.value
            else:
                continue
            if not isinstance(sql, str) or any(isinstance(a, ast.Starred) for a in node.args):
                continue
            wanted = max((int(n) for n in re.findall(r"\$(\d+)", sql)), default=0)
            assert len(node.args) - 1 == wanted, f"{relative(path)}:{node.lineno}"
            checked += 1
    assert checked > 100


# --- names: every table and column the SQL uses exists ----------------------


class _Collect(Visitor):
    """Relations, aliases, and column references of one statement."""

    def __init__(self):
        super().__init__()
        self.relations: set[str] = set()
        self.aliases: dict[str, set[str]] = {}
        self.opaque: set[str] = {"excluded"}  # CTEs, sub-selects, functions: not checked
        self.refs: list[tuple[str, str]] = []
        self.inserts: list[tuple[str, list[str], list[str]]] = []
        self.updates: list[tuple[str, list[str]]] = []

    def visit_RangeVar(self, ancestors, node):
        self.relations.add(node.relname)
        self.aliases.setdefault(node.alias.aliasname if node.alias else node.relname, set()).add(
            node.relname
        )

    def visit_CommonTableExpr(self, ancestors, node):
        self.opaque.add(node.ctename)

    def visit_RangeSubselect(self, ancestors, node):
        if node.alias:
            self.opaque.add(node.alias.aliasname)

    def visit_RangeFunction(self, ancestors, node):
        if node.alias:
            self.opaque.add(node.alias.aliasname)

    def visit_ColumnRef(self, ancestors, node):
        names = [getattr(f, "sval", None) for f in node.fields]
        if len(names) == 2 and None not in names:
            self.refs.append((names[0], names[1]))

    def visit_InsertStmt(self, ancestors, node):
        conflict = node.onConflictClause
        infer = (
            [e.name for e in conflict.infer.indexElems if e.name]
            if conflict and conflict.infer
            else []
        )
        sets = [t.name for t in conflict.targetList or ()] if conflict else []
        self.inserts.append(
            (node.relation.relname, [c.name for c in node.cols or ()], infer + sets)
        )

    def visit_UpdateStmt(self, ancestors, node):
        self.updates.append((node.relation.relname, [t.name for t in node.targetList]))


@pytest.mark.parametrize("path, text, line", ALL_SQL, ids=IDS)
def test_tables_and_columns_exist(path, text, line):
    where = f"{relative(path)}:{line}"
    found = _Collect()
    found(parse_sql(text))
    for relation in found.relations:
        if relation in found.opaque:
            continue
        assert SCHEMA.known(relation), f"{where}: no table or view {relation}"
    insert_targets = {table for table, _, _ in found.inserts}
    for alias, column in found.refs:
        if alias in found.opaque and alias != "excluded":
            continue
        if alias == "excluded":
            relations = insert_targets
        else:
            relations = found.aliases.get(alias)
            assert relations is not None, f"{where}: unknown alias {alias}"
        known = [r for r in relations if SCHEMA.known(r) and r != "users"]
        if known:
            assert any(column in SCHEMA.columns(r) for r in known), f"{where}: {alias}.{column}"
    for table, columns, conflict_columns in found.inserts:
        for column in columns + conflict_columns:
            assert column in SCHEMA.columns(table), f"{where}: insert into {table} ({column})"
    for table, columns in found.updates:
        for column in columns:
            assert column in SCHEMA.columns(table), f"{where}: update {table} set {column}"


def test_the_sql_uses_the_names_the_migrations_gave():
    # Names the code relies on: a rename in a migration must show up here.
    assert {"seq", "feed_seq", "watched_on", "film_id", "private", "deleted_at"} <= set(
        SCHEMA.tables["stubs"]
    )
    assert {"film_id", "ord"} <= set(SCHEMA.views["v_visible_wishes"])
    assert {"viewer_id", "owner_id", "film_id", "film", "rating", "feed_seq", "recency"} == set(
        SCHEMA.views["v_visible_stubs"]
    )
    assert {"user_id", "film_id", "rating", "private"} == set(SCHEMA.views["v_my_stubs"])
