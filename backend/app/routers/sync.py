"""POST /v1/sync/push, GET /v1/sync/pull: the owner's diary, last write wins.

This module reads and writes the owner's tables (`stubs`, `wishes`,
`user_docs`) and their `data` column. No other router may.
"""

from datetime import UTC, datetime
from typing import Annotated, Any
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Query

from app.auth.deps import UserDep
from app.common import ensure_profile
from app.db import DbDep, lock_user
from app.errors import TooLarge
from app.logic.validate import RecordError, Row, validate_record
from app.schemas.phase1 import SyncPull, SyncPush, SyncPushResult

router = APIRouter(prefix="/v1/sync", tags=["sync"])

MAX_BATCH = 200
MAX_ROWS = 20_000  # stubs per user, and wishes per user

# `feed_seq` is taken only for a public, fresh stub ($11). An edit keeps it. A
# private or deleted stub loses it. A row is written only if the incoming
# `updated_at` is strictly newer: a tie keeps the server row.
UPSERT_STUB = """
insert into stubs
  (user_id, id, film_id, rating, private, watched_on, film, data, updated_at, deleted_at, feed_seq)
values
  ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
   case when $11::boolean then nextval('public.feed_seq') end)
on conflict (user_id, id) do update set
  film_id = excluded.film_id,
  rating = excluded.rating,
  private = excluded.private,
  watched_on = excluded.watched_on,
  film = excluded.film,
  data = excluded.data,
  updated_at = excluded.updated_at,
  deleted_at = excluded.deleted_at,
  feed_seq = case
    when excluded.deleted_at is not null or excluded.private then null
    else coalesce(stubs.feed_seq, excluded.feed_seq)
  end
where excluded.updated_at > stubs.updated_at
returning seq
"""

UPSERT_WISH = """
insert into wishes (user_id, film_id, film, data, updated_at, deleted_at)
values ($1, $2, $3, $4, $5, $6)
on conflict (user_id, film_id) do update set
  film = excluded.film,
  data = excluded.data,
  updated_at = excluded.updated_at,
  deleted_at = excluded.deleted_at
where excluded.updated_at > wishes.updated_at
returning seq
"""

UPSERT_DOC = """
insert into user_docs (user_id, kind, data, updated_at, deleted_at)
values ($1, $2, $3, $4, $5)
on conflict (user_id, kind) do update set
  data = excluded.data,
  updated_at = excluded.updated_at,
  deleted_at = excluded.deleted_at
where excluded.updated_at > user_docs.updated_at
returning seq
"""

CURRENT = {
    "stub": """
select 'stub' as kind, id, updated_at, deleted_at is not null as deleted, film, data, seq
from stubs where user_id = $1 and id = $2""",
    "wish": """
select 'wish' as kind, film_id as id, updated_at, deleted_at is not null as deleted, film, data, seq
from wishes where user_id = $1 and film_id = $2""",
    "doc": """
select kind, kind as id, updated_at, deleted_at is not null as deleted,
       null::jsonb as film, data, seq
from user_docs where user_id = $1 and kind = $2""",
}

PULL = """
select kind, id, updated_at, deleted, film, data, seq from (
  (select 'stub' as kind, id, updated_at, deleted_at is not null as deleted, film, data, seq
   from stubs where user_id = $1 and seq > $2 order by seq limit $3)
  union all
  (select 'wish', film_id, updated_at, deleted_at is not null, film, data, seq
   from wishes where user_id = $1 and seq > $2 order by seq limit $3)
  union all
  (select kind, kind, updated_at, deleted_at is not null, null::jsonb, data, seq
   from user_docs where user_id = $1 and seq > $2 order by seq limit $3)
) t
order by seq
limit $3
"""


def _upsert(row: Row, user: UUID) -> tuple[str, tuple[Any, ...], str]:
    """The statement, its arguments, and the key of the CURRENT query for a row."""
    deleted_at = row.updated_at if row.deleted else None
    if row.kind == "stub":
        args = (
            user,
            row.id,
            row.film_id,
            row.rating,
            row.private,
            row.watched_on,
            row.film,
            row.data,
            row.updated_at,
            deleted_at,
            row.fresh,
        )
        return UPSERT_STUB, args, "stub"
    if row.kind == "wish":
        args = (user, row.id, row.film, row.data, row.updated_at, deleted_at)
        return UPSERT_WISH, args, "wish"
    return UPSERT_DOC, (user, row.kind, row.data, row.updated_at, deleted_at), "doc"


def _same(server: asyncpg.Record, row: Row) -> bool:
    """The server already holds exactly this record: a retry, not a conflict."""
    return (
        server["updated_at"] == row.updated_at
        and server["deleted"] == row.deleted
        and server["data"] == row.data
        and server["film"] == row.film
    )


HAVE = {
    "stub": "select id from stubs where user_id = $1 and id = any($2::text[])",
    "wish": "select film_id as id from wishes where user_id = $1 and film_id = any($2::text[])",
}
COUNT = {
    "stub": "select count(*) from stubs where user_id = $1",
    "wish": "select count(*) from wishes where user_id = $1",
}


class _Room:
    """Counts the rows a user holds, so a push cannot go over MAX_ROWS."""

    # ponytail: one count(*) per push for a user near the cap. Keep a counter column if 20,000
    # rows ever make that slow.

    def __init__(self, have: dict[str, set[str]], total: dict[str, int]):
        self.have = have
        self.total = total

    @classmethod
    async def load(cls, c: asyncpg.Connection, user: UUID, rows: list[Row]) -> "_Room":
        have: dict[str, set[str]] = {"stub": set(), "wish": set()}
        total = {"stub": 0, "wish": 0}
        for kind in have:
            ids = [r.id for r in rows if r.kind == kind]
            if ids:
                have[kind] = {r["id"] for r in await c.fetch(HAVE[kind], user, ids)}
                total[kind] = await c.fetchval(COUNT[kind], user)
        return cls(have, total)

    def full(self, row: Row) -> bool:
        if row.kind not in self.have:
            return False
        return row.id not in self.have[row.kind] and self.total[row.kind] >= MAX_ROWS

    def took(self, row: Row) -> None:
        if row.kind in self.have and row.id not in self.have[row.kind]:
            self.have[row.kind].add(row.id)
            self.total[row.kind] += 1


@router.post("/push", response_model=SyncPushResult)
async def push(body: SyncPush, user: UserDep, db: DbDep):
    if len(body.records) > MAX_BATCH:
        raise TooLarge("At most 200 records per push")
    now = datetime.now(UTC)
    rows: list[Row] = []
    rejected: list[dict] = []
    for rec in body.records:
        try:
            args = (rec.kind, rec.id, rec.updated_at, rec.deleted, rec.film, rec.data, now)
            rows.append(validate_record(*args))
        except RecordError as exc:
            rejected.append({"kind": rec.kind, "id": rec.id, "code": exc.code})
    conflicts: list[dict] = []
    async with db.tx() as c:
        await lock_user(c, user)  # seq order = commit order for this user
        await ensure_profile(c, user)
        room = await _Room.load(c, user, rows)
        for row in rows:
            if room.full(row):
                rejected.append({"kind": row.kind, "id": row.id, "code": "limit_reached"})
                continue
            sql, args, current = _upsert(row, user)
            if await c.fetchval(sql, *args) is not None:
                room.took(row)
                continue
            server = await c.fetchrow(CURRENT[current], *args[:2])
            if not _same(server, row):
                conflicts.append(dict(server))
    return {"server_time": now, "conflicts": conflicts, "rejected": rejected}


@router.get("/pull", response_model=SyncPull)
async def pull(
    user: UserDep,
    db: DbDep,
    after: Annotated[int, Query(ge=0, le=2**62)] = 0,
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
):
    records = await db.fetch(PULL, user, after, limit + 1)
    more = len(records) > limit
    records = records[:limit]
    return {
        "server_time": datetime.now(UTC),
        "records": [dict(r) for r in records],
        "cursor": records[-1]["seq"] if records else after,
        "more": more,
    }
