"""GET /v1/feed: what friends watched, reactions to my films, films sent to me.

Order is `feed_seq`, newest first. No item holds a date. The ids are
`<w|r|s>:<feed_seq>`, unique because the three sources share one counter.
"""

from typing import Annotated

from fastapi import APIRouter, Query

from app.auth.deps import UserDep
from app.common import card
from app.db import DbDep
from app.errors import BadRequest
from app.logic.cursor import BadCursor, decode_cursor, encode_cursor
from app.schemas.phase2 import Feed

router = APIRouter(prefix="/v1", tags=["feed"])

# $1 = me, $2 = cursor (last feed_seq seen, or null), $3 = how many rows to read.
FEED = """
with watched as (
  select 'w' as src, v.feed_seq, v.owner_id as user_id, v.film_id, v.film, v.rating,
         null::smallint as reaction, null::text as note
  from v_visible_stubs v
  where v.viewer_id = $1 and v.owner_id <> $1 and v.feed_seq is not null
    and ($2::bigint is null or v.feed_seq < $2)
  order by v.feed_seq desc
  limit $3
), reacted as (
  select 'r', x.feed_seq, x.user_id, x.film_id, x.film, null::double precision,
         x.reaction, null::text
  from reactions x
  where x.target_id = $1 and not blocked_either($1, x.user_id)
    and ($2::bigint is null or x.feed_seq < $2)
  order by x.feed_seq desc
  limit $3
), sent as (
  select 's', x.feed_seq, x.sender_id, x.film_id, x.film, null::double precision,
         null::smallint, x.note
  from sent_films x
  where x.receiver_id = $1 and not blocked_either($1, x.sender_id)
    and ($2::bigint is null or x.feed_seq < $2)
  order by x.feed_seq desc
  limit $3
), merged as (
  select * from watched
  union all select * from reacted
  union all select * from sent
)
select m.src, m.feed_seq, m.film_id, m.film, m.rating, m.reaction, m.note,
       p.id, p.handle, p.display_name, p.avatar_color,
       mine.reaction as my_reaction
from (select * from merged order by feed_seq desc limit $3) m
join profiles p on p.id = m.user_id
left join reactions mine
  on m.src = 'w' and mine.user_id = $1 and mine.target_id = m.user_id and mine.film_id = m.film_id
order by m.feed_seq desc
"""

KINDS = {"w": "watched", "r": "reaction", "s": "sent"}


@router.get("/feed", response_model=Feed)
async def feed(
    user: UserDep,
    db: DbDep,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
):
    try:
        after = decode_cursor(cursor)
    except BadCursor as exc:
        raise BadRequest("bad_cursor", "The cursor is not valid") from exc
    rows = await db.fetch(FEED, user, after, limit + 1)
    more = len(rows) > limit
    rows = rows[:limit]
    items = [
        {
            "id": f"{r['src']}:{r['feed_seq']}",
            "kind": KINDS[r["src"]],
            "user": card(r),
            "film_id": r["film_id"],
            "film": r["film"],
            "rating": r["rating"],
            "reaction": r["reaction"],
            "note": r["note"],
            "my_reaction": r["my_reaction"],
        }
        for r in rows
    ]
    return {"items": items, "next_cursor": encode_cursor(rows[-1]["feed_seq"]) if more else None}
