"""The group deck, its inputs, and swipes.

Seen rule: a film is seen if (a) it is in the caller's own stubs, (b) it is in a
stub the caller could already see on that member's profile (friend, profile
shared, not private), or (c) any member swiped `seen` on it. A film counts per
member for `seen_by`, but no response names a member.
"""

from uuid import UUID

from fastapi import APIRouter

from app.auth.deps import UserDep
from app.common import film_or_error
from app.db import DbDep
from app.errors import Conflict, Invalid
from app.members import acting_member, seat_of
from app.ratelimit import LimiterDep
from app.schemas.phase3 import (
    Deck,
    DeckInputs,
    DeckPut,
    DeckPutResult,
    SwipesPut,
    SwipesResult,
    Tallies,
)

router = APIRouter(prefix="/v1/groups", tags=["decks"])

DECK = "select version, items from group_decks where group_id = $1"

# $1 = group, $2 = caller, $3 = the film ids to check. Rows are (film, member)
# pairs, so a member who counts twice still counts once. A member either of us
# blocked does not count (guests have no user and always count). Membership
# stays; only the blocked counterpart's contributions are hidden.
SEEN_BY = """
select film_id, count(*) as n from (
  select film_id, member_id from swipes
  where group_id = $1 and vote = 'seen' and film_id = any($3::text[])
    and (member_id is null or not blocked_either($2, member_id))
  union
  select v.film_id, m.id from group_members m
  join v_my_stubs v on v.user_id = m.user_id
  where m.group_id = $1 and m.user_id = $2 and v.film_id = any($3::text[])
  union
  select v.film_id, m.id from group_members m
  join v_visible_stubs v on v.owner_id = m.user_id
  where m.group_id = $1 and m.user_id <> $2 and v.viewer_id = $2 and v.film_id = any($3::text[])
    and not blocked_either($2, v.owner_id)
) pairs
group by film_id
"""

SEEN_ALL = """
select film_id from (
  select film_id from swipes where group_id = $1 and vote = 'seen'
    and (member_id is null or not blocked_either($2, member_id))
  union
  select film_id from v_my_stubs where user_id = $2
  union
  select v.film_id from group_members m
  join v_visible_stubs v on v.owner_id = m.user_id
  where m.group_id = $1 and m.user_id <> $2 and v.viewer_id = $2
    and not blocked_either($2, v.owner_id)
) seen
order by film_id
limit 20000
"""

# Every member's watchlist plus the shared list. `n` counts the sources.
WANTED = """
select film_id, (array_agg(film))[1] as film, count(*) as n from (
  select film_id, film from v_group_wishes where group_id = $1
  union all
  select film_id, film from group_films where group_id = $1
) sources
group by film_id
order by n desc, film_id
limit 2000
"""

TASTES = "select taste from v_group_tastes where group_id = $1"

PUT_SWIPES = """
insert into swipes (group_id, member_id, film_id, vote)
select $1::uuid, t.member_id, t.film_id, t.vote
from jsonb_to_recordset($2::jsonb) as t(member_id uuid, film_id text, vote text)
on conflict (member_id, film_id) do update set vote = excluded.vote
"""

# $2 = caller: a member either of us blocked does not count (guests always do).
TALLIES = """
select film_id, vote, count(*) as n from swipes
where group_id = $1 and (member_id is null or not blocked_either($2, member_id))
group by film_id, vote
"""
MINE = "select film_id, vote from swipes where member_id = $1"


@router.get("/{gid}/deck", response_model=Deck)
async def get_deck(gid: UUID, user: UserDep, db: DbDep):
    async with db.conn() as c:
        await seat_of(c, gid, user)
        deck = await c.fetchrow(DECK, gid)
        ids = [item["film_id"] for item in deck["items"]]
        seen = {r["film_id"]: r["n"] for r in await c.fetch(SEEN_BY, gid, user, ids)}
    items = [{**item, "seen_by": seen.get(item["film_id"], 0)} for item in deck["items"]]
    return {"version": deck["version"], "items": items}


@router.put("/{gid}/deck", response_model=DeckPutResult)
async def put_deck(gid: UUID, body: DeckPut, user: UserDep, db: DbDep, limiter: LimiterDep):
    items = [{"film_id": i.film_id, "film": film_or_error(i.film, i.film_id)} for i in body.items]
    if len({i["film_id"] for i in items}) != len(items):
        raise Invalid("A film is in the deck twice")
    async with db.tx() as c:
        await seat_of(c, gid, user)
        limiter.check("deck", f"{gid}:{user}")  # one write per 10 seconds per member per group
        version = await c.fetchval(
            "update group_decks set version = version + 1, items = $3, updated_at = now() "
            "where group_id = $1 and version = $2 returning version",
            gid,
            body.base_version,
            items,
        )
        if version is None:
            current = await c.fetchval("select version from group_decks where group_id = $1", gid)
            raise Conflict("deck_conflict", "The deck changed", {"current_version": current})
    return {"version": version}


@router.get("/{gid}/deck-inputs", response_model=DeckInputs)
async def deck_inputs(gid: UUID, user: UserDep, db: DbDep):
    async with db.conn() as c:
        await seat_of(c, gid, user)
        tastes = await c.fetch(TASTES, gid)
        seen = await c.fetch(SEEN_ALL, gid, user)
        wanted = await c.fetch(WANTED, gid)
    return {
        "tastes": [r["taste"] for r in tastes],
        "seen": [r["film_id"] for r in seen],
        "wanted": [dict(r) for r in wanted],
    }


@router.put("/{gid}/swipes", response_model=SwipesResult)
async def put_swipes(gid: UUID, body: SwipesPut, user: UserDep, db: DbDep):
    async with db.tx() as c:
        seat = await seat_of(c, gid, user)
        targets: dict[UUID | None, UUID] = {}
        latest: dict[tuple[UUID, str], str] = {}  # the last vote for a film wins
        for swipe in body.swipes:
            if swipe.member_id not in targets:
                targets[swipe.member_id] = await acting_member(c, gid, seat, swipe.member_id)
            latest[(targets[swipe.member_id], swipe.film_id)] = swipe.vote
        rows = [
            {"member_id": str(member), "film_id": film, "vote": vote}
            for (member, film), vote in latest.items()
        ]
        await c.execute(PUT_SWIPES, gid, rows)
    return {"saved": len(rows)}


@router.get("/{gid}/tallies", response_model=Tallies)
async def tallies(gid: UUID, user: UserDep, db: DbDep, member_id: UUID | None = None):
    async with db.conn() as c:
        seat = await seat_of(c, gid, user)
        member = await acting_member(c, gid, seat, member_id)
        counted = await c.fetch(TALLIES, gid, user)
        mine = await c.fetch(MINE, member)
    totals: dict[str, dict[str, int]] = {}
    for row in counted:
        totals.setdefault(row["film_id"], {"want": 0, "skip": 0, "seen": 0})[row["vote"]] = row["n"]
    return {"tallies": totals, "mine": {r["film_id"]: r["vote"] for r in mine}}
