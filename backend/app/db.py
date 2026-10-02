"""The asyncpg pool.

The pool works behind a transaction pooler (Supabase Supavisor, pgbouncer), so
the code never uses: prepared statements, SET, LISTEN, session advisory locks,
or temp tables. Locks are pg_advisory_xact_lock inside a transaction.

The pool is created on the first query, so the app boots with no database.
"""

import asyncio
import json
import logging
import time
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from typing import Annotated, Any
from uuid import UUID

import asyncpg
from fastapi import Depends, Request

from app.errors import DbUnavailable

log = logging.getLogger("talkies")

_RETRY_AFTER_FAILURE = 2.0
_HEALTH_CACHE = 5.0


async def _init(conn: asyncpg.Connection) -> None:
    # jsonb in and out as Python objects. Text format: no binary version byte.
    await conn.set_type_codec(
        "jsonb",
        encoder=lambda value: json.dumps(value, default=str),
        decoder=json.loads,
        schema="pg_catalog",
    )


class Db:
    def __init__(
        self,
        dsn: str,
        max_size: int = 10,
        clock: Callable[[], float] = time.monotonic,
    ):
        self._dsn = dsn
        self._max_size = max_size
        self._clock = clock
        self._pool: asyncpg.Pool | None = None
        self._lock = asyncio.Lock()
        self._failed_at: float | None = None
        self._health: tuple[float, bool] | None = None

    def _recently_failed(self) -> bool:
        failed = self._failed_at
        return failed is not None and self._clock() - failed < _RETRY_AFTER_FAILURE

    async def pool(self) -> asyncpg.Pool:
        if self._pool is not None:
            return self._pool
        if not self._dsn or self._recently_failed():
            raise DbUnavailable()
        async with self._lock:
            # Requests that waited here must not each wait for a failing connect.
            if self._pool is None:
                if self._recently_failed():
                    raise DbUnavailable()
                self._pool = await self._connect()
        return self._pool

    async def _connect(self) -> asyncpg.Pool:
        try:
            pool = await asyncpg.create_pool(
                self._dsn,
                min_size=1,
                max_size=self._max_size,
                statement_cache_size=0,
                command_timeout=15,
                timeout=5,
                init=_init,
            )
        except Exception as exc:  # any connect failure means "not reachable"
            self._failed_at = self._clock()
            log.warning("database not reachable: %s", type(exc).__name__)
            raise DbUnavailable() from exc
        self._failed_at = None
        return pool

    @asynccontextmanager
    async def conn(self) -> AsyncIterator[asyncpg.Connection]:
        pool = await self.pool()
        try:
            connection = await pool.acquire(timeout=5)
        except Exception as exc:
            # An established pool loses its connections when the database goes
            # away. Drop it and start the same cooldown as a failed connect, or
            # every request waits out the acquire timeout against a dead pool.
            await self._discard(pool, exc)
            raise DbUnavailable() from exc
        try:
            yield connection
        finally:
            await pool.release(connection)

    async def _discard(self, pool: asyncpg.Pool, exc: Exception) -> None:
        async with self._lock:
            if self._pool is not pool:
                return  # another request already replaced it
            self._pool = None
            self._failed_at = self._clock()
        log.warning("database connection lost: %s", type(exc).__name__)
        try:
            await pool.close()
        except Exception:  # closing a broken pool is best effort
            log.info("closing the broken pool failed")

    @asynccontextmanager
    async def tx(self) -> AsyncIterator[asyncpg.Connection]:
        async with self.conn() as connection, connection.transaction():
            yield connection

    async def fetch(self, sql: str, *args: Any) -> list[asyncpg.Record]:
        async with self.conn() as c:
            return await c.fetch(sql, *args)

    async def fetchrow(self, sql: str, *args: Any) -> asyncpg.Record | None:
        async with self.conn() as c:
            return await c.fetchrow(sql, *args)

    async def fetchval(self, sql: str, *args: Any) -> Any:
        async with self.conn() as c:
            return await c.fetchval(sql, *args)

    async def execute(self, sql: str, *args: Any) -> str:
        async with self.conn() as c:
            return await c.execute(sql, *args)

    async def healthy(self) -> bool:
        """True when `select 1` works. The answer is reused for 5 seconds."""
        now = self._clock()
        if self._health is not None and now - self._health[0] < _HEALTH_CACHE:
            return self._health[1]
        ok = await self._ping()
        self._health = (self._clock(), ok)
        return ok

    async def _ping(self) -> bool:
        try:
            async with self.conn() as c:
                await asyncio.wait_for(c.fetchval("select 1"), 3)
        except Exception as exc:  # a health check reports, it never raises
            log.info("health check failed: %s", type(exc).__name__)
            return False
        return True

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None


# Every user-keyed write takes this lock first (sync push, wrap-up, delete), so
# `seq` order matches commit order for that user. The key is the same one that
# delete_account() uses in SQL.
LOCK_USER = "select pg_advisory_xact_lock(hashtextextended($1::text, 0))"


async def lock_user(c: asyncpg.Connection, user_id: UUID) -> None:
    await c.execute(LOCK_USER, str(user_id))


# Two users who act on each other (friend requests) take one lock for the pair,
# so two requests that cross never leave two pending rows behind.
LOCK_PAIR = "select pg_advisory_xact_lock(hashtextextended($1::text || ':' || $2::text, 1))"


async def lock_pair(c: asyncpg.Connection, a: UUID, b: UUID) -> None:
    first, second = sorted((str(a), str(b)))
    await c.execute(LOCK_PAIR, first, second)


def get_db(request: Request) -> Db:
    return request.app.state.db


DbDep = Annotated[Db, Depends(get_db)]
