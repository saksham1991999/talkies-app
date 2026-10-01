"""Reactions, blocks, and reports."""

from uuid import UUID

from fastapi import APIRouter, Response

from app.auth.deps import UserDep
from app.common import card
from app.db import DbDep
from app.errors import Invalid, NotFound
from app.ratelimit import LimiterDep
from app.schemas.phase2 import BlockList, BlockPost, ReactionPut, ReportPost, ReportResult

router = APIRouter(prefix="/v1", tags=["safety"])

# I may react only to a film I can see on that person's profile.
VISIBLE_FILM = """
select film from v_visible_stubs
where viewer_id = $1 and owner_id = $2 and film_id = $3
order by recency
limit 1
"""
REACT = """
insert into reactions (user_id, target_id, film_id, film, reaction)
values ($1, $2, $3, $4, $5)
on conflict (user_id, target_id, film_id) do update set
  film = excluded.film,
  reaction = excluded.reaction,
  feed_seq = nextval('public.feed_seq')
"""
CLEAR = "delete from reactions where user_id = $1 and target_id = $2 and film_id = $3"

BLOCKED = """
select p.id, p.handle, p.display_name, p.avatar_color
from blocks b join profiles p on p.id = b.blocked_id
where b.blocker_id = $1
order by lower(coalesce(p.display_name, p.handle, '')), p.id
"""

# A message I can see in a group I belong to.
MESSAGE = """
select m.group_id, m.sender_id, m.body, m.film_id, m.night_id, m.created_at
from messages m
join group_members gm on gm.group_id = m.group_id and gm.user_id = $1
where m.id = $2 and m.kind = 'text' and not blocked_either($1, m.sender_id)
"""
MY_GROUP = """
select g.name from groups g join group_members m on m.group_id = g.id
where g.id = $1 and m.user_id = $2
"""
REPORT = """
insert into reports (reporter_id, target_user_id, kind, target_id, reason, note, snapshot)
values ($1, $2, $3, $4, $5, $6, $7)
returning id
"""
# A user I may report: someone in my audience (a friend, or myself), or a member
# of a group I am in. This keeps the endpoint from probing arbitrary uuids.
AUDIENCE = """
select not exists (
  select 1 from v_audience where viewer_id = $1 and owner_id = $2
) and not exists (
  select 1
  from group_members a join group_members b on a.group_id = b.group_id
  where a.user_id = $1 and b.user_id = $2
) as stranger
"""


@router.put("/reactions", status_code=204)
async def put_reaction(body: ReactionPut, user: UserDep, db: DbDep):
    if body.user_id == user:
        raise Invalid()
    async with db.tx() as c:
        if body.reaction is None:
            await c.execute(CLEAR, user, body.user_id, body.film_id)
        else:
            film = await c.fetchval(VISIBLE_FILM, user, body.user_id, body.film_id)
            if film is None:
                raise NotFound()
            await c.execute(REACT, user, body.user_id, body.film_id, film, body.reaction)
    return Response(status_code=204)


@router.get("/blocks", response_model=BlockList)
async def list_blocks(user: UserDep, db: DbDep):
    return {"items": [card(r) for r in await db.fetch(BLOCKED, user)]}


@router.post("/blocks", status_code=204)
async def block(body: BlockPost, user: UserDep, db: DbDep):
    other = body.user_id
    if other == user:
        raise Invalid()
    async with db.tx() as c:
        if await c.fetchval("select 1 from profiles where id = $1", other) is None:
            raise NotFound()
        await c.execute(
            "insert into blocks (blocker_id, blocked_id) values ($1, $2) on conflict do nothing",
            user,
            other,
        )
        await c.execute(
            "delete from friendships "
            "where (user_id = $1 and friend_id = $2) or (user_id = $2 and friend_id = $1)",
            user,
            other,
        )
        await c.execute(
            "delete from friend_requests "
            "where (from_id = $1 and to_id = $2) or (from_id = $2 and to_id = $1)",
            user,
            other,
        )
        # Reactions and sent films go both ways, so nothing resurfaces on unblock.
        await c.execute(
            "delete from reactions "
            "where (user_id = $1 and target_id = $2) or (user_id = $2 and target_id = $1)",
            user,
            other,
        )
        await c.execute(
            "delete from sent_films "
            "where (sender_id = $1 and receiver_id = $2) or (sender_id = $2 and receiver_id = $1)",
            user,
            other,
        )
    return Response(status_code=204)


@router.delete("/blocks/{uid}", status_code=204)
async def unblock(uid: UUID, user: UserDep, db: DbDep):
    await db.execute("delete from blocks where blocker_id = $1 and blocked_id = $2", user, uid)
    return Response(status_code=204)


async def _target(c, user: UUID, body: ReportPost) -> tuple[UUID | None, dict | None]:
    """The reported user and a snapshot, after checking that the reporter may see the target."""
    if body.kind == "message":
        if not (body.target_id.isascii() and body.target_id.isdigit() and len(body.target_id) < 19):
            raise Invalid()
        row = await c.fetchrow(MESSAGE, user, int(body.target_id))
        if row is None:
            raise NotFound()
        if row["sender_id"] == user:
            raise Invalid()
        snapshot = {
            "group_id": str(row["group_id"]),
            "sender_id": str(row["sender_id"]),
            "body": row["body"],
            "film_id": row["film_id"],
            "night_id": None if row["night_id"] is None else str(row["night_id"]),
            "sent_at": row["created_at"].isoformat(),
        }
        return row["sender_id"], snapshot
    try:
        target = UUID(body.target_id)
    except ValueError as exc:
        raise Invalid() from exc
    if body.kind == "user":
        if target == user:
            raise Invalid()
        # 404 for anyone outside my audience or groups: no existence oracle.
        if await c.fetchval(AUDIENCE, user, target):
            raise NotFound()
        return target, None
    name = await c.fetchval(MY_GROUP, target, user)
    if name is None:
        raise NotFound()
    return None, {"name": name}


@router.post("/reports", response_model=ReportResult)
async def report(body: ReportPost, user: UserDep, db: DbDep, limiter: LimiterDep):
    limiter.check("report", str(user))
    async with db.tx() as c:
        target_user, snapshot = await _target(c, user, body)
        report_id = await c.fetchval(
            REPORT, user, target_user, body.kind, body.target_id, body.reason, body.note, snapshot
        )
    return {"id": report_id}
