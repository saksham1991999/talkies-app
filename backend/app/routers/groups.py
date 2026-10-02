"""Groups: create, join, members, guests, invite code, shared list."""

import secrets
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Path, Response

from app.auth.deps import UserDep
from app.common import ensure_profile, film_or_error, guest_color
from app.db import DbDep, lock_user
from app.errors import Conflict, NotFound
from app.logic.validate import INVITE_RE
from app.members import post_system, require_owner, seat_of
from app.ratelimit import LimiterDep
from app.schemas.phase3 import (
    Group,
    GroupCreate,
    GroupDetail,
    GroupFilmPut,
    GroupFilms,
    GroupList,
    GroupPatch,
    GuestPost,
    InviteCode,
    JoinPost,
    Member,
)

router = APIRouter(prefix="/v1/groups", tags=["groups"])

MAX_GROUPS = 20  # per user
MAX_MEMBERS = 30  # per group, guests included
MAX_FILMS = 200  # on the shared list
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # A-HJ-KM-NP-Z2-9

QID_PATH = Path(pattern=r"^Q[0-9]{1,12}$")

GROUP = """
select g.id, g.name, g.invite_code, d.version as deck_version,
       (select count(*) from group_members m where m.group_id = g.id) as member_count
from groups g join group_decks d on d.group_id = g.id
where g.id = $1
"""
MY_GROUPS = """
select g.id, g.name, g.invite_code, d.version as deck_version,
       (select count(*) from group_members m where m.group_id = g.id) as member_count
from groups g join group_decks d on d.group_id = g.id
where g.id in (select group_id from group_members where user_id = $1)
order by g.created_at, g.id
"""
# Members the caller may see: a blocked user is hidden in both directions.
MEMBERS = """
select m.id, m.user_id, m.guest_name, p.handle, p.display_name, p.avatar_color,
       coalesce(m.user_id = g.owner_id, false) as owner,
       coalesce(m.user_id = $2, false) as me
from group_members m
join groups g on g.id = m.group_id
left join profiles p on p.id = m.user_id
where m.group_id = $1
  and (m.user_id is null or m.user_id = $2 or not blocked_either($2, m.user_id))
order by m.joined_at, m.id
"""
MEMBER_COUNT = "select count(*) from group_members where group_id = $1"
GROUP_COUNT = "select count(*) from group_members where user_id = $1"
LOCK_GROUP = "select owner_id from groups where id = $1 for update"
ADD_USER = "insert into group_members (group_id, user_id) values ($1, $2)"
USER_NAME = "select coalesce(display_name, handle, 'Member') from profiles where id = $1"
MEMBER_NAME = """
select m.user_id, coalesce(m.guest_name, p.display_name, p.handle, 'Member') as name
from group_members m left join profiles p on p.id = m.user_id
where m.id = $1 and m.group_id = $2
"""


def new_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(8))


def member_json(row) -> dict:
    guest = row["guest_name"] is not None
    name = row["guest_name"] or row["display_name"] or row["handle"] or "Member"
    return {
        "id": row["id"],
        "name": name,
        "avatar_color": guest_color(name) if guest else row["avatar_color"],
        "handle": row["handle"],
        "guest": guest,
        "owner": row["owner"],
        "me": row["me"],
    }


@router.post("", status_code=201, response_model=Group)
async def create_group(body: GroupCreate, user: UserDep, db: DbDep):
    async with db.tx() as c:
        await lock_user(c, user)
        await ensure_profile(c, user)
        if await c.fetchval(GROUP_COUNT, user) >= MAX_GROUPS:
            raise Conflict("group_limit", "You are in 20 groups already")
        group_id = None
        for _ in range(8):  # a code clash is very unlikely: 31^8 codes
            group_id = await c.fetchval(
                "insert into groups (name, owner_id, invite_code) values ($1, $2, $3) "
                "on conflict (invite_code) do nothing returning id",
                body.name,
                user,
                new_code(),
            )
            if group_id is not None:
                break
        if group_id is None:
            raise RuntimeError("no free invite code")
        await c.execute(ADD_USER, group_id, user)
        await c.execute("insert into group_decks (group_id) values ($1)", group_id)
        row = await c.fetchrow(GROUP, group_id)
    return dict(row)


@router.get("", response_model=GroupList)
async def list_groups(user: UserDep, db: DbDep):
    return {"items": [dict(r) for r in await db.fetch(MY_GROUPS, user)]}


@router.post("/join", response_model=Group)
async def join_group(body: JoinPost, user: UserDep, db: DbDep, limiter: LimiterDep):
    limiter.check("join", str(user))
    code = "".join(body.code.split()).upper()  # people type spaces: "K7M2 QX9P"
    async with db.tx() as c:
        await lock_user(c, user)
        await ensure_profile(c, user)
        found = None
        if INVITE_RE.fullmatch(code):
            found = await c.fetchval(
                "select id from groups where invite_code = $1 for update", code
            )
        if found is None:
            raise NotFound("invalid_code", "That code does not match a group")
        member = await c.fetchval(
            "select 1 from group_members where group_id = $1 and user_id = $2", found, user
        )
        if member is None:
            if await c.fetchval(GROUP_COUNT, user) >= MAX_GROUPS:
                raise Conflict("group_limit", "You are in 20 groups already")
            if await c.fetchval(MEMBER_COUNT, found) >= MAX_MEMBERS:
                raise Conflict("group_full", "The group has 30 members")
            await c.execute(ADD_USER, found, user)
            name = await c.fetchval(USER_NAME, user)
            await post_system(c, found, "joined", {"name": name}, None, user)
        row = await c.fetchrow(GROUP, found)
    return dict(row)


@router.get("/{gid}", response_model=GroupDetail)
async def get_group(gid: UUID, user: UserDep, db: DbDep):
    async with db.conn() as c:
        await seat_of(c, gid, user)
        group = await c.fetchrow(GROUP, gid)
        members = await c.fetch(MEMBERS, gid, user)
    return {**dict(group), "members": [member_json(r) for r in members]}


@router.patch("/{gid}", response_model=Group)
async def rename_group(gid: UUID, body: GroupPatch, user: UserDep, db: DbDep):
    async with db.tx() as c:
        # The group row first, as remove_member does: an ownership handover that
        # is in flight cannot land between the owner check and the update.
        if await c.fetchval(LOCK_GROUP, gid) is None:
            raise NotFound()
        require_owner(await seat_of(c, gid, user))
        await c.execute("update groups set name = $2 where id = $1", gid, body.name)
        row = await c.fetchrow(GROUP, gid)
    return dict(row)


@router.delete("/{gid}", status_code=204)
async def delete_group(gid: UUID, user: UserDep, db: DbDep):
    async with db.tx() as c:
        if await c.fetchval(LOCK_GROUP, gid) is None:
            raise NotFound()
        require_owner(await seat_of(c, gid, user))
        await c.execute("delete from groups where id = $1", gid)
    return Response(status_code=204)


@router.post("/{gid}/invite/rotate", response_model=InviteCode)
async def rotate_invite(gid: UUID, user: UserDep, db: DbDep):
    async with db.tx() as c:
        if await c.fetchval(LOCK_GROUP, gid) is None:
            raise NotFound()
        require_owner(await seat_of(c, gid, user))
        for _ in range(8):
            code = await c.fetchval(
                "update groups set invite_code = $2 where id = $1 "
                "and not exists (select 1 from groups where invite_code = $2) "
                "returning invite_code",
                gid,
                new_code(),
            )
            if code is not None:
                return {"invite_code": code}
    raise RuntimeError("no free invite code")


@router.delete("/{gid}/members/{mid}", status_code=204)
async def remove_member(gid: UUID, mid: str, user: UserDep, db: DbDep):
    """Leave (`mid` is `me` or my member id) or, for the owner, remove someone else."""
    async with db.tx() as c:
        owner_id = await c.fetchval(LOCK_GROUP, gid)  # also keeps joins and leaves in order
        if owner_id is None:
            raise NotFound()
        seat = await seat_of(c, gid, user)
        target = seat.member_id if mid == "me" else _member_id(mid)
        row = await c.fetchrow(MEMBER_NAME, target, gid)
        if row is None:
            raise NotFound()
        if target != seat.member_id:
            require_owner(seat)
        await c.execute("delete from group_members where id = $1", target)
        if row["user_id"] == owner_id and not await _hand_over(c, gid):
            return Response(status_code=204)  # nobody was left: the group is gone
        await post_system(c, gid, "left", {"name": row["name"]}, None, row["user_id"])
    return Response(status_code=204)


def _member_id(text: str) -> UUID:
    try:
        return UUID(text)
    except ValueError as exc:
        raise NotFound() from exc


async def _hand_over(c, gid: UUID) -> bool:
    """The owner left: the earliest-joined account member takes over.

    Returns False when nobody is left and the group was deleted.
    """
    heir = await c.fetchval(
        "select user_id from group_members where group_id = $1 and user_id is not null "
        "order by joined_at, id limit 1",
        gid,
    )
    if heir is None:
        await c.execute("delete from groups where id = $1", gid)
        return False
    await c.execute("update groups set owner_id = $2 where id = $1", gid, heir)
    return True


@router.post("/{gid}/guests", status_code=201, response_model=Member)
async def add_guest(gid: UUID, body: GuestPost, user: UserDep, db: DbDep):
    async with db.tx() as c:
        if await c.fetchval(LOCK_GROUP, gid) is None:
            raise NotFound()
        require_owner(await seat_of(c, gid, user))
        if await c.fetchval(MEMBER_COUNT, gid) >= MAX_MEMBERS:
            raise Conflict("group_full", "The group has 30 members")
        taken = await c.fetchval(
            "select 1 from group_members where group_id = $1 and lower(guest_name) = lower($2)",
            gid,
            body.name,
        )
        if taken is not None:
            raise Conflict("name_taken", "A guest has that name already")
        member_id = await c.fetchval(
            "insert into group_members (group_id, guest_name) values ($1, $2) returning id",
            gid,
            body.name,
        )
    return {
        "id": member_id,
        "name": body.name,
        "avatar_color": guest_color(body.name),
        "handle": None,
        "guest": True,
        "owner": False,
        "me": False,
    }


@router.get("/{gid}/films", response_model=GroupFilms)
async def list_films(gid: UUID, user: UserDep, db: DbDep):
    async with db.conn() as c:
        await seat_of(c, gid, user)
        rows = await c.fetch(
            "select film_id, film from group_films where group_id = $1 order by added_at, film_id",
            gid,
        )
    return {"items": [dict(r) for r in rows]}


@router.put("/{gid}/films/{film_id}", status_code=204)
async def put_film(
    gid: UUID, film_id: Annotated[str, QID_PATH], body: GroupFilmPut, user: UserDep, db: DbDep
):
    film = film_or_error(body.film, film_id)
    async with db.tx() as c:
        if await c.fetchval(LOCK_GROUP, gid) is None:
            raise NotFound()
        await seat_of(c, gid, user)
        known = await c.fetchval(
            "select 1 from group_films where group_id = $1 and film_id = $2", gid, film_id
        )
        if known is None:
            count = await c.fetchval("select count(*) from group_films where group_id = $1", gid)
            if count >= MAX_FILMS:
                raise Conflict("list_full", "The shared list has 200 films")
        await c.execute(
            "insert into group_films (group_id, film_id, film) values ($1, $2, $3) "
            "on conflict (group_id, film_id) do update set film = excluded.film",
            gid,
            film_id,
            film,
        )
    return Response(status_code=204)


@router.delete("/{gid}/films/{film_id}", status_code=204)
async def remove_film(gid: UUID, film_id: Annotated[str, QID_PATH], user: UserDep, db: DbDep):
    async with db.tx() as c:
        await seat_of(c, gid, user)
        await c.execute(
            "delete from group_films where group_id = $1 and film_id = $2", gid, film_id
        )
    return Response(status_code=204)
