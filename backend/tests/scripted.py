"""A database stand-in for route tests that cannot reach Postgres.

Each test lists, in order, the SQL the route must run (a fragment that has to
appear in it) and the rows to answer with. That checks the Python around the
SQL: the order of calls, the arguments, and that the reply fits its model. It
does not run any SQL. The SQL is checked by tests/pure/test_sql.py and by
tests/db when a database is available.
"""

from contextlib import asynccontextmanager
from typing import Any

from app.auth.deps import ACCOUNT_EXISTS
from app.db import Db


class _Transaction:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class ScriptedConn:
    def __init__(self, *steps: tuple[str, Any]):
        self.steps = list(steps)
        self.calls: list[tuple[str, str, tuple]] = []

    def _take(self, kind: str, sql: str, args: tuple) -> Any:
        assert self.steps, f"unexpected {kind}: {sql.strip()[:120]}"
        fragment, result = self.steps.pop(0)
        flat = " ".join(sql.split())
        assert fragment in flat, f"expected {fragment!r}, the route ran: {flat[:160]}"
        self.calls.append((kind, flat, args))
        if isinstance(result, Exception):
            raise result
        return result

    async def fetch(self, sql: str, *args: Any):
        return self._take("fetch", sql, args)

    async def fetchrow(self, sql: str, *args: Any):
        return self._take("fetchrow", sql, args)

    async def fetchval(self, sql: str, *args: Any):
        return self._take("fetchval", sql, args)

    async def execute(self, sql: str, *args: Any):
        return self._take("execute", sql, args)

    def transaction(self) -> _Transaction:
        return _Transaction()

    def args_of(self, fragment: str) -> tuple:
        """The arguments of the first call whose SQL holds `fragment`."""
        for _, sql, args in self.calls:
            if fragment in sql:
                return args
        raise AssertionError(f"no call with {fragment!r}")

    def finished(self) -> None:
        assert not self.steps, f"the route skipped: {[fragment for fragment, _ in self.steps]}"


class ScriptedDb(Db):
    def __init__(self, conn: ScriptedConn):
        super().__init__("")
        self.scripted = conn

    async def fetchrow(self, sql: str, *args: Any):
        # Every signed-in request checks that the account still exists. These
        # tests are about the route's own SQL, so answer that one call here
        # instead of making every script start with it.
        if " ".join(sql.split()) == ACCOUNT_EXISTS:
            return {"?column?": 1}
        return await super().fetchrow(sql, *args)

    @asynccontextmanager
    async def conn(self):
        yield self.scripted

    @asynccontextmanager
    async def tx(self):
        yield self.scripted
