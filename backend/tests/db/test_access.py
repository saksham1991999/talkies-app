"""The Supabase public API roles must reach nothing."""

import asyncpg
import pytest

PROBES = [
    "select * from profiles",
    "select * from stubs",
    "select * from wishes",
    "select * from user_docs",
    "select * from friendships",
    "select * from messages",
    "select * from v_visible_stubs",
    "select * from v_visible_wishes",
    "select * from v_audience",
    "select * from v_my_stubs",
    "select * from v_group_tastes",
    "insert into blocks (blocker_id, blocked_id) values (gen_random_uuid(), gen_random_uuid())",
    "delete from profiles",
    "select delete_account(gen_random_uuid())",
    "select blocked_either(gen_random_uuid(), gen_random_uuid())",
    "select nextval('sync_seq')",
    "select nextval('feed_seq')",
]


async def test_every_table_has_rls_on_and_there_is_no_policy(world):
    tables = await world.rows(
        "select c.relname, c.relrowsecurity from pg_class c "
        "join pg_namespace n on n.oid = c.relnamespace "
        "where n.nspname = 'public' and c.relkind = 'r'"
    )
    assert len(tables) >= 20
    assert [t["relname"] for t in tables if not t["relrowsecurity"]] == []
    # Only `public`: a policy another schema carries (a Supabase default, say)
    # is not this migration's business, and this test must not fail over it.
    policies = await world.value("select count(*) from pg_policies where schemaname = 'public'")
    assert policies == 0


@pytest.mark.parametrize("role", ["anon", "authenticated"])
async def test_the_public_api_roles_hold_no_privilege(world, role):
    gaps = await world.rows(
        "select c.relname, c.relkind from pg_class c "
        "join pg_namespace n on n.oid = c.relnamespace "
        "where n.nspname = 'public' and c.relkind in ('r', 'v', 'S') and ("
        "  (c.relkind in ('r', 'v') and has_table_privilege($1, c.oid, "
        "     'select, insert, update, delete, truncate, references, trigger'))"
        "  or (c.relkind = 'S' and has_sequence_privilege($1, c.oid, 'usage, select, update')))",
        role,
    )
    assert [g["relname"] for g in gaps] == []
    functions = await world.rows(
        "select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
        "where n.nspname = 'public' and has_function_privilege($1, p.oid, 'execute')",
        role,
    )
    assert [f["proname"] for f in functions] == []


@pytest.mark.parametrize("role", ["anon", "authenticated"])
async def test_set_role_is_denied_everywhere(world, role):
    await world.user("asha")  # there is something to read
    for sql in PROBES:
        await world.pg.execute(f"set role {role}")
        try:
            with pytest.raises(asyncpg.InsufficientPrivilegeError):
                await world.pg.execute(sql)
        finally:
            await world.pg.execute("reset role")


async def test_a_new_table_does_not_inherit_a_grant(world):
    """The migration headers revoke the default grants. Hosted Supabase would add them otherwise."""
    await world.pg.execute("create table zz_probe (x int)")
    try:
        for role in ("anon", "authenticated"):
            assert (
                await world.value("select has_table_privilege($1, 'zz_probe', 'select')", role)
                is False
            )
    finally:
        await world.pg.execute("drop table zz_probe")
