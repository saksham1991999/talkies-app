"""POST /v1/nights/{nid}/wrapup: one stub in each account member's diary.

This module writes into the owners' `stubs` table. It does it on purpose: the
stub appears in each person's own diary, as if their phone had pushed it.
"""

import random
from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter

from app.auth.deps import UserDep
from app.db import DbDep, lock_user
from app.errors import Conflict, NotFound
from app.logic.validate import format_time, is_fresh
from app.logic.wrapup import Attendee, StubPlan, plan_wrapup
from app.members import post_system
from app.routers.nights import night_and_seat, require_host
from app.schemas.phase5 import WrapupPost, WrapupResult

router = APIRouter(prefix="/v1", tags=["wrapup"])

# The chosen film and slot of a night that is set.
EVENT = """
select n.tz_offset_min, n.place, f.film_id, f.film, s.starts_at
from nights n
join night_options f on f.night_id = n.id and f.kind = 'film' and f.chosen
join night_options s on s.night_id = n.id and s.kind = 'slot' and s.chosen
where n.id = $1
"""
# Who went: the members who said yes, in member order.
WENT = """
select m.id, m.user_id, coalesce(m.guest_name, p.display_name, p.handle, 'Member') as name
from group_members m
left join profiles p on p.id = m.user_id
join night_rsvps r on r.member_id = m.id and r.night_id = $2 and r.response = 'yes'
where m.group_id = $1
order by m.joined_at, m.id
"""
# Who went, when the host names the members.
NAMED = """
select m.id, m.user_id, coalesce(m.guest_name, p.display_name, p.handle, 'Member') as name
from group_members m
left join profiles p on p.id = m.user_id
where m.group_id = $1 and m.id = any($2::uuid[])
order by m.joined_at, m.id
"""
# Account members of a group, in a fixed order. A wrap-up locks every one of
# them before it touches the night row, so a lock held for account deletion can
# never wait on a night that holds a user lock (account deletion takes the user
# lock first, then deletes the nights).
GROUP_USERS = """
select user_id from group_members
where group_id = $1 and user_id is not null
order by user_id
"""
NIGHT_GROUP = "select group_id, status from nights where id = $1"
# A stub the user deleted stays deleted (the tombstone row blocks the insert).
INSERT_STUB = """
insert into stubs
  (user_id, id, film_id, rating, private, watched_on, film, data, updated_at, feed_seq)
values
  ($1, $2, $3, null, false, $4, $5, $6, $7,
   case when $8::boolean then nextval('public.feed_seq') end)
on conflict (user_id, id) do nothing
returning seq
"""


def _stub_data(plan: StubPlan, film_id: str, place: str | None, now: datetime) -> dict:
    """The phone's own stub JSON. `no: 0` means the phone assigns the ticket number."""
    data = {
        "id": plan.stub_id,
        "no": 0,
        "film": film_id,
        "created": format_time(now),
        "date": plan.local_date.isoformat(),
        "prec": "day",
        "seat": plan.seat,
    }
    if place:
        data["place"] = place
    if plan.company:
        data["with"] = plan.company
    return data


@router.post("/nights/{nid}/wrapup", response_model=WrapupResult)
async def wrap_up(nid: UUID, body: WrapupPost, user: UserDep, db: DbDep):
    now = datetime.now(UTC)
    async with db.tx() as c:
        # One lock order for the whole app: user locks, then the night row.
        # Account deletion locks the user and then deletes its nights, so taking
        # the night row first here could deadlock with it.
        known = await c.fetchrow(NIGHT_GROUP, nid)
        if known is None:
            raise NotFound()
        for row in await c.fetch(GROUP_USERS, known["group_id"]):
            await lock_user(c, row["user_id"])
        night, seat = await night_and_seat(c, nid, user, lock=True)
        require_host(night, seat, user)
        event = await c.fetchrow(EVENT, nid) if night["status"] in ("set", "done") else None
        if event is None:
            raise Conflict("not_set", "The night is not set")
        if body.member_ids is None:
            rows = await c.fetch(WENT, night["group_id"], nid)
        else:
            rows = await c.fetch(NAMED, night["group_id"], body.member_ids)
        attendees = [Attendee(r["name"], r["user_id"]) for r in rows]
        plans = plan_wrapup(
            nid,
            event["starts_at"],
            event["tz_offset_min"],
            attendees,
            random.Random(),
            body.seat_row,
            body.first_seat,
        )
        created = 0
        for plan in plans:
            data = _stub_data(plan, event["film_id"], event["place"], now)
            fresh = is_fresh(plan.local_date, now)
            args = (
                plan.user_id,
                plan.stub_id,
                event["film_id"],
                plan.local_date,
                event["film"],
                data,
                now,
                fresh,
            )
            if await c.fetchval(INSERT_STUB, *args) is not None:
                created += 1
        # Done even when nobody gets a stub: a guest-only or empty wrap-up still
        # closes the night, or it would stay `set` and could be wrapped again.
        if night["status"] == "set":
            await c.execute("update nights set status = 'done' where id = $1", nid)
            await post_system(c, night["group_id"], "wrapped", {"night_id": str(nid)}, nid)
    return {"created": created, "skipped": len(plans) - created}
