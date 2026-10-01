"""Group chat and "send a film"."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query

from app.auth.deps import UserDep
from app.common import film_or_error
from app.db import DbDep
from app.errors import Invalid, NotFound
from app.members import seat_of
from app.ratelimit import LimiterDep
from app.schemas.common import Empty
from app.schemas.phase5 import Message, MessageList, MessagePost, SendFilm

router = APIRouter(prefix="/v1", tags=["chat"])

# $1 group, $2 after (id or null), $3 before (id or null), $4 me, $5 rows to read.
# With `after` the rows come oldest first. Otherwise newest first (the caller
# reverses them), so "the latest page" and "the page before N" are the same query.
# A blocked user's messages are hidden from the blocker and the reverse.
MESSAGES = """
select m.id, m.kind, m.body, m.code, m.args, m.film_id, m.film, m.night_id, m.created_at,
       p.id as sender_id, p.handle, p.display_name, p.avatar_color
from messages m
left join profiles p on p.id = m.sender_id
where m.group_id = $1
  and ($2::bigint is null or m.id > $2)
  and ($3::bigint is null or m.id < $3)
  and (m.sender_id is null or not blocked_either($4, m.sender_id))
  and (m.subject_id is null or not blocked_either($4, m.subject_id))
order by (case when $2::bigint is not null then m.id end) asc nulls last, m.id desc
limit $5
"""
INSERT_MESSAGE = """
insert into messages (group_id, sender_id, kind, body, film_id, film, night_id)
values ($1, $2, 'text', $3, $4, $5, $6)
returning id, created_at
"""
SENDER = "select id, handle, display_name, avatar_color from profiles where id = $1"
CAN_SEND = """
select 1 from friendships where user_id = $1 and friend_id = $2 and not blocked_either($1, $2)
"""
SEND = """
insert into sent_films (sender_id, receiver_id, film_id, film, note)
values ($1, $2, $3, $4, $5)
"""


def _sender(row) -> dict | None:
    if row["sender_id"] is None:
        return None
    return {
        "id": row["sender_id"],
        "handle": row["handle"],
        "display_name": row["display_name"],
        "avatar_color": row["avatar_color"],
    }


def _message(row) -> dict:
    return {
        "id": row["id"],
        "kind": row["kind"],
        "sender": _sender(row),
        "body": row["body"],
        "code": row["code"],
        "args": row["args"],
        "film_id": row["film_id"],
        "film": row["film"],
        "night_id": row["night_id"],
        "created_at": row["created_at"],
    }


@router.get("/groups/{gid}/messages", response_model=MessageList)
async def list_messages(
    gid: UUID,
    user: UserDep,
    db: DbDep,
    after: Annotated[int | None, Query(ge=0, le=2**62)] = None,
    before: Annotated[int | None, Query(ge=0, le=2**62)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
):
    if after is not None and before is not None:
        raise Invalid("Use after or before, not both")
    async with db.conn() as c:
        await seat_of(c, gid, user)
        rows = await c.fetch(MESSAGES, gid, after, before, user, limit + 1)
    more = len(rows) > limit
    rows = rows[:limit]
    if after is None:
        rows.reverse()
    return {"items": [_message(r) for r in rows], "has_more": more}


@router.post("/groups/{gid}/messages", status_code=201, response_model=Message)
async def post_message(gid: UUID, body: MessagePost, user: UserDep, db: DbDep, limiter: LimiterDep):
    limiter.check("message", str(user))
    if (body.film_id is None) != (body.film is None):
        raise Invalid("A film needs both film_id and film")
    film = film_or_error(body.film, body.film_id) if body.film is not None else None
    async with db.tx() as c:
        await seat_of(c, gid, user)
        if body.night_id is not None:
            found = await c.fetchval(
                "select 1 from nights where id = $1 and group_id = $2", body.night_id, gid
            )
            if found is None:
                raise Invalid("That night is not in this group")
        row = await c.fetchrow(
            INSERT_MESSAGE, gid, user, body.body, body.film_id, film, body.night_id
        )
        me = await c.fetchrow(SENDER, user)
    return {
        "id": row["id"],
        "kind": "text",
        "sender": dict(me),
        "body": body.body,
        "code": None,
        "args": None,
        "film_id": body.film_id,
        "film": film,
        "night_id": body.night_id,
        "created_at": row["created_at"],
    }


@router.post("/films/send", status_code=201, response_model=Empty)
async def send_film(body: SendFilm, user: UserDep, db: DbDep, limiter: LimiterDep):
    if body.user_id == user:
        raise Invalid()
    limiter.check("send_film", str(user))
    film = film_or_error(body.film, body.film_id)
    async with db.tx() as c:
        if await c.fetchval(CAN_SEND, user, body.user_id) is None:
            raise NotFound()  # not a friend, or blocked either way
        await c.execute(SEND, user, body.user_id, body.film_id, film, body.note or None)
    return {}
