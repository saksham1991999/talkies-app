"""Movie nights: a poll over films and time slots, then an event with RSVPs."""

from collections import defaultdict
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Response

from app.auth.deps import UserDep
from app.common import film_or_error
from app.db import DbDep
from app.errors import Conflict, Forbidden, Invalid, NotFound
from app.logic.validate import format_time
from app.members import Seat, acting_member, post_system, seat_of
from app.schemas.phase4 import (
    ClosePost,
    Night,
    NightCreate,
    NightList,
    RsvpPut,
    VotesPut,
    VotesResult,
)

router = APIRouter(prefix="/v1", tags=["nights"])

SLOT_PAST = timedelta(days=1)
SLOT_FUTURE = timedelta(days=400)

LATEST = "select id from nights where group_id = $1 order by created_at desc, id desc limit 50"
NIGHTS = """
select id, group_id, host_id, status, tz_offset_min, place
from nights where id = any($1::uuid[])
"""
OPTIONS = """
select o.night_id, o.id, o.kind, o.position, o.film_id, o.film, o.starts_at, o.chosen,
       (select count(*) from night_votes v where v.option_id = o.id) as approvals
from night_options o
where o.night_id = any($1::uuid[])
order by o.night_id, o.kind, o.position
"""
VOTES_OF = """
select o.night_id, v.option_id
from night_votes v join night_options o on o.id = v.option_id
where v.member_id = $2 and o.night_id = any($1::uuid[])
"""
RSVPS = """
select night_id, member_id, response from night_rsvps
where night_id = any($1::uuid[])
order by night_id, member_id
"""
LOCK_NIGHT = "select group_id, host_id, status from nights where id = $1 for update"

INSERT_NIGHT = """
insert into nights (group_id, host_id, status, tz_offset_min, place)
values ($1, $2, $3, $4, $5)
returning id
"""
INSERT_FILMS = """
insert into night_options (night_id, kind, position, film_id, film, chosen)
select $1::uuid, 'film', t.position, t.film_id, t.film, $3::boolean
from jsonb_to_recordset($2::jsonb) as t(position smallint, film_id text, film jsonb)
"""
INSERT_SLOTS = """
insert into night_options (night_id, kind, position, starts_at, chosen)
select $1::uuid, 'slot', t.position, t.starts_at, $3::boolean
from jsonb_to_recordset($2::jsonb) as t(position smallint, starts_at timestamptz)
"""


async def load_nights(c: asyncpg.Connection, ids: list[UUID], member: UUID) -> list[dict[str, Any]]:
    """The `night` JSON for each id, in the order given. `mine` is for `member`."""
    if not ids:
        return []
    nights = {r["id"]: r for r in await c.fetch(NIGHTS, ids)}
    options: dict[UUID, list] = defaultdict(list)
    for r in await c.fetch(OPTIONS, ids):
        options[r["night_id"]].append(r)
    mine: dict[UUID, list[UUID]] = defaultdict(list)
    for r in await c.fetch(VOTES_OF, ids, member):
        mine[r["night_id"]].append(r["option_id"])
    replies: dict[UUID, list] = defaultdict(list)
    for r in await c.fetch(RSVPS, ids):
        replies[r["night_id"]].append({"member_id": r["member_id"], "response": r["response"]})
    return [_night_json(nights[i], options[i], mine[i], replies[i]) for i in ids if i in nights]


def _night_json(night, options, mine, rsvps) -> dict[str, Any]:
    chosen = {o["kind"]: o for o in options if o["chosen"]}
    event = None
    if night["status"] in ("set", "done") and len(chosen) == 2:
        event = {
            "film_id": chosen["film"]["film_id"],
            "film": chosen["film"]["film"],
            "starts_at": chosen["slot"]["starts_at"],
            "tz_offset_min": night["tz_offset_min"],
            "place": night["place"],
        }
    return {
        "id": night["id"],
        "group_id": night["group_id"],
        "status": night["status"],
        "host_id": night["host_id"],
        "tz_offset_min": night["tz_offset_min"],
        "place": night["place"],
        "options": [
            {
                "id": o["id"],
                "kind": o["kind"],
                "position": o["position"],
                "film_id": o["film_id"],
                "film": o["film"],
                "starts_at": o["starts_at"],
                "approvals": o["approvals"],
            }
            for o in options
        ],
        "mine": mine,
        "event": event,
        "rsvps": rsvps,
    }


async def night_and_seat(
    c: asyncpg.Connection, night_id: UUID, user: UUID, lock: bool = False
) -> tuple[asyncpg.Record, Seat]:
    """The night row and the caller's seat in its group. 404 if either is missing."""
    sql = LOCK_NIGHT if lock else "select group_id, host_id, status from nights where id = $1"
    night = await c.fetchrow(sql, night_id)
    if night is None:
        raise NotFound()
    return night, await seat_of(c, night["group_id"], user)


def require_host(night: asyncpg.Record, seat: Seat, user: UUID) -> None:
    """The night host or the group owner."""
    if not (seat.owner or night["host_id"] == user):
        raise Forbidden()


@router.post("/groups/{gid}/nights", status_code=201, response_model=Night)
async def create_night(gid: UUID, body: NightCreate, user: UserDep, db: DbDep):
    now = datetime.now(UTC)
    if any(not now - SLOT_PAST <= slot <= now + SLOT_FUTURE for slot in body.slots):
        raise Invalid("A time slot is out of range")
    if len(set(body.slots)) != len(body.slots):
        raise Invalid("A time slot is listed twice")
    films = [
        {"position": i, "film_id": f.film_id, "film": film_or_error(f.film, f.film_id)}
        for i, f in enumerate(body.films)
    ]
    if len({f["film_id"] for f in films}) != len(films):
        raise Invalid("A film is listed twice")
    slots = [{"position": i, "starts_at": format_time(s)} for i, s in enumerate(body.slots)]
    fixed = len(films) == 1 and len(slots) == 1  # one film and one slot: no poll needed
    async with db.tx() as c:
        seat = await seat_of(c, gid, user)
        night_id = await c.fetchval(
            INSERT_NIGHT, gid, user, "set" if fixed else "poll", body.tz_offset_min, body.place
        )
        await c.execute(INSERT_FILMS, night_id, films, fixed)
        await c.execute(INSERT_SLOTS, night_id, slots, fixed)
        if fixed:
            args = {
                "night_id": str(night_id),
                "film_id": films[0]["film_id"],
                "starts_at": slots[0]["starts_at"],
            }
            await post_system(c, gid, "night_set", args, night_id)
        else:
            await post_system(c, gid, "poll_open", {"night_id": str(night_id)}, night_id)
        night = (await load_nights(c, [night_id], seat.member_id))[0]
    return night


@router.get("/groups/{gid}/nights", response_model=NightList)
async def list_nights(gid: UUID, user: UserDep, db: DbDep):
    async with db.conn() as c:
        seat = await seat_of(c, gid, user)
        ids = [r["id"] for r in await c.fetch(LATEST, gid)]
        return {"items": await load_nights(c, ids, seat.member_id)}


@router.get("/nights/{nid}", response_model=Night)
async def get_night(nid: UUID, user: UserDep, db: DbDep, member_id: UUID | None = None):
    async with db.conn() as c:
        night, seat = await night_and_seat(c, nid, user)
        member = await acting_member(c, night["group_id"], seat, member_id)
        found = await load_nights(c, [nid], member)
    return found[0]


@router.delete("/nights/{nid}", status_code=204)
async def delete_night(nid: UUID, user: UserDep, db: DbDep):
    async with db.tx() as c:
        night, seat = await night_and_seat(c, nid, user)
        require_host(night, seat, user)
        await c.execute("delete from nights where id = $1", nid)
    return Response(status_code=204)


@router.put("/nights/{nid}/votes", response_model=VotesResult)
async def put_votes(nid: UUID, body: VotesPut, user: UserDep, db: DbDep):
    """Replace the member's approvals with `option_ids`."""
    async with db.tx() as c:
        night, seat = await night_and_seat(c, nid, user, lock=True)
        member = await acting_member(c, night["group_id"], seat, body.member_id)
        if night["status"] != "poll":
            raise Conflict("not_polling", "The poll is closed")
        found = await c.fetch("select id from night_options where night_id = $1", nid)
        valid = {r["id"] for r in found}
        approved = set(body.option_ids)
        if not approved <= valid:
            raise Invalid("An option is not part of this night")
        await c.execute(
            "delete from night_votes where member_id = $1 "
            "and option_id in (select id from night_options where night_id = $2)",
            member,
            nid,
        )
        if approved:
            await c.execute(
                "insert into night_votes (option_id, member_id) "
                "select unnest($1::uuid[]), $2::uuid",
                list(approved),
                member,
            )
        counts = await c.fetch(
            "select o.id, count(v.member_id) as n from night_options o "
            "left join night_votes v on v.option_id = o.id where o.night_id = $1 group by o.id",
            nid,
        )
    return {"approvals": {str(r["id"]): r["n"] for r in counts}}


def _winner(options: list, kind: str, picked: UUID | None):
    """The option the host picked, or the one with most approvals (ties: lowest position)."""
    of_kind = [o for o in options if o["kind"] == kind]
    if picked is not None:
        match = [o for o in of_kind if o["id"] == picked]
        if not match:
            raise Invalid("An option is not part of this night")
        return match[0]
    return min(of_kind, key=lambda o: (-o["approvals"], o["position"]))


@router.post("/nights/{nid}/close", response_model=Night)
async def close_night(nid: UUID, body: ClosePost, user: UserDep, db: DbDep):
    async with db.tx() as c:
        night, seat = await night_and_seat(c, nid, user, lock=True)
        require_host(night, seat, user)
        if night["status"] != "poll":
            raise Conflict("not_polling", "The poll is closed")
        options = await c.fetch(OPTIONS, [nid])
        film = _winner(options, "film", body.film_option_id)
        slot = _winner(options, "slot", body.slot_option_id)
        await c.execute(
            "update night_options set chosen = true where id = any($1::uuid[])",
            [film["id"], slot["id"]],
        )
        await c.execute(
            "update nights set status = 'set', place = coalesce($2, place) where id = $1",
            nid,
            body.place,
        )
        args = {
            "night_id": str(nid),
            "film_id": film["film_id"],
            "starts_at": format_time(slot["starts_at"]),
        }
        await post_system(c, night["group_id"], "night_set", args, nid)
        found = await load_nights(c, [nid], seat.member_id)
    return found[0]


@router.put("/nights/{nid}/rsvp", status_code=204)
async def put_rsvp(nid: UUID, body: RsvpPut, user: UserDep, db: DbDep):
    async with db.tx() as c:
        night, seat = await night_and_seat(c, nid, user, lock=True)
        member = await acting_member(c, night["group_id"], seat, body.member_id)
        if night["status"] != "set":
            raise Conflict("not_set", "The night is not set")
        await c.execute(
            "insert into night_rsvps (night_id, member_id, response) values ($1, $2, $3) "
            "on conflict (night_id, member_id) do update set response = excluded.response",
            nid,
            member,
            body.response,
        )
    return Response(status_code=204)
