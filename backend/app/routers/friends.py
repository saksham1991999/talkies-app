"""Friend requests and the friend list (with taste match)."""

from uuid import UUID

from fastapi import APIRouter, Response

from app.auth.deps import UserDep
from app.common import card
from app.db import DbDep, lock_pair
from app.errors import Conflict, Invalid, NotFound
from app.logic.match import Match, match_score
from app.ratelimit import LimiterDep
from app.schemas.phase2 import (
    FriendList,
    FriendRequestPost,
    FriendRequestResult,
    FriendRequests,
)

router = APIRouter(prefix="/v1", tags=["friends"])

# $1 = me, $2 = the other user. Blocked users do not exist for each other.
EXISTS_UNBLOCKED = "select 1 from profiles p where p.id = $2 and not blocked_either($1, p.id)"
ARE_FRIENDS = "select 1 from friendships where user_id = $1 and friend_id = $2"
HAS_REQUESTED = "select 1 from friend_requests where from_id = $1 and to_id = $2"
TAKE_REQUEST = "delete from friend_requests where from_id = $2 and to_id = $1 returning 1"
MAKE_FRIENDS = """
insert into friendships (user_id, friend_id) values ($1, $2), ($2, $1)
on conflict do nothing
"""

INCOMING = """
select p.id, p.handle, p.display_name, p.avatar_color
from friend_requests r join profiles p on p.id = r.from_id
where r.to_id = $1 and not blocked_either($1, p.id)
order by lower(coalesce(p.display_name, p.handle, '')), p.id
"""
OUTGOING = """
select p.id, p.handle, p.display_name, p.avatar_color
from friend_requests r join profiles p on p.id = r.to_id
where r.from_id = $1 and not blocked_either($1, p.id)
order by lower(coalesce(p.display_name, p.handle, '')), p.id
"""

FRIENDS = """
select p.id, p.handle, p.display_name, p.avatar_color,
       (p.visibility = 'friends') as visible, p.share_ratings
from friendships f join profiles p on p.id = f.friend_id
where f.user_id = $1 and not blocked_either($1, f.friend_id)
order by lower(coalesce(p.display_name, p.handle, '')), p.id
limit 500
"""

# ponytail: this scans the public films of every friend on each call. Fine for tens of
# friends. Cache the counts per user if a profile list gets slow.
# One query for every friend on the page. `mine` is my own films (private ones
# too, QID only). `theirs` is what each friend shows me. A rating the friend
# hides is already null in the view. `common` is (my best, their best) per
# shared film.
MATCHES = """
with mine as (
  select film_id, max(rating) as best from v_my_stubs where user_id = $1 group by film_id
), theirs as (
  select owner_id, film_id, max(rating) as best
  from v_visible_stubs
  where viewer_id = $1 and owner_id = any($2::uuid[])
  group by owner_id, film_id
)
select t.owner_id,
       count(*) as n_theirs,
       (select count(*) from mine) as n_mine,
       coalesce(
         jsonb_agg(jsonb_build_array(m.best, t.best)) filter (where m.film_id is not null),
         '[]'::jsonb
       ) as common
from theirs t
left join mine m on m.film_id = t.film_id
group by t.owner_id
"""


async def match_for(c, viewer: UUID, owners: dict[UUID, bool]) -> dict[UUID, Match]:
    """The match of `viewer` with each owner. `owners` maps an owner to share_ratings."""
    if not owners:
        return {}
    found = {}
    for row in await c.fetch(MATCHES, viewer, list(owners)):
        pairs = [(a, b) for a, b in row["common"]]
        found[row["owner_id"]] = match_score(
            row["n_mine"], row["n_theirs"], pairs, owners[row["owner_id"]]
        )
    return {owner: found.get(owner, Match(0, None)) for owner in owners}


@router.post("/friends/requests", response_model=FriendRequestResult)
async def send_request(body: FriendRequestPost, user: UserDep, db: DbDep, limiter: LimiterDep):
    other = body.user_id
    if other == user:
        raise Invalid()
    limiter.check("friend_request", str(user))
    async with db.tx() as c:
        await lock_pair(c, user, other)
        if await c.fetchval(EXISTS_UNBLOCKED, user, other) is None:
            raise NotFound()
        if await c.fetchval(ARE_FRIENDS, user, other) is not None:
            return {"status": "friends"}
        if await c.fetchval(HAS_REQUESTED, user, other) is not None:
            raise Conflict("already_pending", "A request is already waiting")
        if await c.fetchval(TAKE_REQUEST, user, other) is not None:  # a mutual request accepts
            await c.execute(MAKE_FRIENDS, user, other)
            return {"status": "friends"}
        await c.execute("insert into friend_requests (from_id, to_id) values ($1, $2)", user, other)
    return {"status": "pending"}


@router.get("/friends/requests", response_model=FriendRequests)
async def list_requests(user: UserDep, db: DbDep):
    async with db.conn() as c:
        incoming = await c.fetch(INCOMING, user)
        outgoing = await c.fetch(OUTGOING, user)
    return {"incoming": [card(r) for r in incoming], "outgoing": [card(r) for r in outgoing]}


@router.post("/friends/requests/{uid}/accept", status_code=204)
async def accept_request(uid: UUID, user: UserDep, db: DbDep):
    async with db.tx() as c:
        await lock_pair(c, user, uid)
        if await c.fetchval(EXISTS_UNBLOCKED, user, uid) is None:
            raise NotFound()
        if await c.fetchval(TAKE_REQUEST, user, uid) is None:
            raise NotFound()
        await c.execute(MAKE_FRIENDS, user, uid)
    return Response(status_code=204)


@router.delete("/friends/requests/{uid}", status_code=204)
async def drop_request(uid: UUID, user: UserDep, db: DbDep):
    """Decline a request from `uid`, or cancel one sent to `uid`."""
    done = await db.execute(
        "delete from friend_requests "
        "where (from_id = $1 and to_id = $2) or (from_id = $2 and to_id = $1)",
        user,
        uid,
    )
    if done == "DELETE 0":
        raise NotFound()
    return Response(status_code=204)


@router.get("/friends", response_model=FriendList)
async def list_friends(user: UserDep, db: DbDep):
    async with db.conn() as c:
        friends = await c.fetch(FRIENDS, user)
        shared = {r["id"]: r["share_ratings"] for r in friends if r["visible"]}
        matches = await match_for(c, user, shared)
    return {
        "items": [
            {
                "card": card(r),
                "visible": r["visible"],
                "match": _wire(matches[r["id"]]) if r["visible"] else None,
            }
            for r in friends
        ]
    }


def _wire(match: Match) -> dict:
    return {"both": match.both, "pct": match.pct}


@router.delete("/friends/{uid}", status_code=204)
async def unfriend(uid: UUID, user: UserDep, db: DbDep):
    await db.execute(
        "delete from friendships "
        "where (user_id = $1 and friend_id = $2) or (user_id = $2 and friend_id = $1)",
        user,
        uid,
    )
    return Response(status_code=204)
