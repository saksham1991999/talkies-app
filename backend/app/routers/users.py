"""Look up a person, read a profile and a shelf, see who watched a film.

Another person's films come only from the views (v_visible_stubs,
v_visible_wishes). They carry no `data` column and no date.
"""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Path, Query

from app.auth.deps import UserDep
from app.common import card
from app.db import DbDep
from app.errors import BadRequest, NotFound
from app.logic.cursor import BadCursor, decode_cursor, encode_cursor
from app.logic.validate import HANDLE_RE
from app.ratelimit import LimiterDep
from app.routers.friends import match_for
from app.schemas.phase2 import FriendsWhoWatched, Lookup, ProfileView, Shelf

router = APIRouter(prefix="/v1", tags=["users"])

LOOKUP = """
select p.id, p.handle, p.display_name, p.avatar_color,
  case
    when exists (select 1 from friendships f where f.user_id = $1 and f.friend_id = p.id)
      then 'friend'
    when exists (select 1 from friend_requests r where r.from_id = p.id and r.to_id = $1)
      then 'incoming'
    when exists (select 1 from friend_requests r where r.from_id = $1 and r.to_id = p.id)
      then 'outgoing'
    else 'none'
  end as relation
from profiles p
where p.handle = $2 and p.id <> $1 and not blocked_either($1, p.id)
"""

# A row only when I may look: I am the owner, or a friend of a shared profile.
AUDIENCE = """
select p.id, p.handle, p.display_name, p.avatar_color,
       (p.visibility = 'friends') as visible, p.share_ratings
from v_audience a join profiles p on p.id = a.owner_id
where a.viewer_id = $1 and a.owner_id = $2
"""

AUDIENCE_ID = "select 1 from v_audience where viewer_id = $1 and owner_id = $2"

STATS = """
select count(distinct film_id) as films, count(*) as viewings, avg(rating) as avg_rating
from v_visible_stubs
where viewer_id = $1 and owner_id = $2
"""

# Genres and languages of the distinct films, counted per film. The film column
# holds the app's own snapshot, so a bad shape is guarded, not trusted. A value
# a film lists twice counts once for that film. The film id rides in pairs so
# UNION drops a repeat of one film's own value, not a second film's row: the
# outer count then adds up films, never rows.
TRAITS = """
with f as (
  select distinct on (film_id) film_id, film
  from v_visible_stubs
  where viewer_id = $1 and owner_id = $2
  order by film_id, recency
), pairs as (
  select f.film_id, 'g' as kind, x.value as name from f
  cross join lateral jsonb_array_elements_text(
    case when jsonb_typeof(f.film -> 'g') = 'array' then f.film -> 'g' else '[]'::jsonb end
  ) as x(value)
  union
  select f.film_id, 'l', x.value from f
  cross join lateral jsonb_array_elements_text(
    case when jsonb_typeof(f.film -> 'l') = 'array' then f.film -> 'l' else '[]'::jsonb end
  ) as x(value)
)
select kind, name, count(*) as n from pairs group by kind, name
"""

# Ratings shared: best rating first. Not shared: most viewings first. Ties: the
# most recent watch (a rank, never a date), then the film id.
TOP_FILMS = """
select film_id, (array_agg(film order by recency))[1] as film, max(rating) as rating
from v_visible_stubs
where viewer_id = $1 and owner_id = $2
group by film_id
order by (case when $3::boolean then max(rating) end) desc nulls last,
         (case when $3::boolean then 0 else count(*) end) desc,
         min(recency),
         film_id
limit 10
"""

WATCHLIST = """
select film_id, film
from v_visible_wishes
where viewer_id = $1 and owner_id = $2
order by ord desc, film_id
limit 50
"""

SHELF = """
select film_id, (array_agg(film order by recency))[1] as film,
       max(rating) as rating, count(*) as viewings
from v_visible_stubs
where viewer_id = $1 and owner_id = $2
group by film_id
order by min(recency), film_id
offset $3 limit $4
"""

WATCHERS = """
select p.id, p.handle, p.display_name, p.avatar_color, max(v.rating) as rating
from v_visible_stubs v join profiles p on p.id = v.owner_id
where v.viewer_id = $1 and v.owner_id <> $1 and v.film_id = $2
group by p.id
order by lower(coalesce(p.display_name, p.handle, '')), p.id
limit 100
"""


@router.get("/users/lookup", response_model=Lookup)
async def lookup(
    handle: Annotated[str, Query(min_length=1, max_length=64)],
    user: UserDep,
    db: DbDep,
    limiter: LimiterDep,
):
    limiter.check("lookup", str(user))
    name = handle.strip().removeprefix("@").lower()
    row = await db.fetchrow(LOOKUP, user, name) if HANDLE_RE.fullmatch(name) else None
    if row is None:
        raise NotFound()
    return {"card": card(row), "relation": row["relation"]}


def _top(rows, kind: str) -> list[str]:
    counted = sorted((r for r in rows if r["kind"] == kind), key=lambda r: (-r["n"], r["name"]))
    return [r["name"] for r in counted[:3]]


@router.get("/users/{uid}", response_model=ProfileView)
async def profile(uid: UUID, user: UserDep, db: DbDep):
    async with db.conn() as c:
        owner = await c.fetchrow(AUDIENCE, user, uid)
        if owner is None:
            raise NotFound()
        stats = await c.fetchrow(STATS, user, uid)
        traits = await c.fetch(TRAITS, user, uid)
        top = await c.fetch(TOP_FILMS, user, uid, owner["share_ratings"])
        wishes = await c.fetch(WATCHLIST, user, uid)
        match = None
        if uid != user:
            found = await match_for(c, user, {uid: owner["share_ratings"]})
            match = {"both": found[uid].both, "pct": found[uid].pct}
    average = stats["avg_rating"]
    return {
        "card": card(owner),
        "relation": "self" if uid == user else "friend",
        "visible": owner["visible"],
        "match": match,
        "stats": {
            "films": stats["films"],
            "viewings": stats["viewings"],
            "avg_rating": None if average is None else round(average, 2),
            "top_genres": _top(traits, "g"),
            "top_langs": _top(traits, "l"),
        },
        "top_films": [dict(r) for r in top],
        "watchlist": [dict(r) for r in wishes],
    }


@router.get("/users/{uid}/films", response_model=Shelf)
async def shelf(
    uid: UUID,
    user: UserDep,
    db: DbDep,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
):
    try:
        offset = decode_cursor(cursor) or 0
    except BadCursor as exc:
        raise BadRequest("bad_cursor", "The cursor is not valid") from exc
    async with db.conn() as c:
        # Your own shelf is not served here: the app builds it from the diary on the phone.
        allowed = uid != user and await c.fetchval(AUDIENCE_ID, user, uid) is not None
        if not allowed:
            raise NotFound()
        rows = await c.fetch(SHELF, user, uid, offset, limit + 1)
    more = len(rows) > limit
    return {
        "items": [dict(r) for r in rows[:limit]],
        "next_cursor": encode_cursor(offset + limit) if more else None,
    }


@router.get("/films/{film_id}/friends", response_model=FriendsWhoWatched)
async def friends_who_watched(
    film_id: Annotated[str, Path(pattern=r"^Q[0-9]{1,12}$")], user: UserDep, db: DbDep
):
    rows = await db.fetch(WATCHERS, user, film_id)
    return {"items": [{"user": card(r), "rating": r["rating"]} for r in rows]}
