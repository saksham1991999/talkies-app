"""Who I am inside a group, and the system messages a group gets."""

from dataclasses import dataclass
from typing import Any
from uuid import UUID

import asyncpg

from app.errors import Forbidden, NotFound

SEAT = """
select m.id, g.owner_id = $2 as owner
from group_members m join groups g on g.id = m.group_id
where m.group_id = $1 and m.user_id = $2
"""
GUEST = "select 1 from group_members where id = $1 and group_id = $2 and user_id is null"
SYSTEM_MESSAGE = """
insert into messages (group_id, kind, code, args, night_id, subject_id)
values ($1, 'system', $2, $3, $4, $5)
"""


@dataclass(frozen=True)
class Seat:
    """The caller's place in a group."""

    member_id: UUID
    owner: bool


async def seat_of(c: asyncpg.Connection, group_id: UUID, user: UUID) -> Seat:
    """The caller's seat. 404 when the caller is not in the group (or it does not exist)."""
    row = await c.fetchrow(SEAT, group_id, user)
    if row is None:
        raise NotFound()
    return Seat(row["id"], row["owner"])


def require_owner(seat: Seat) -> None:
    if not seat.owner:
        raise Forbidden()


async def acting_member(
    c: asyncpg.Connection, group_id: UUID, seat: Seat, member_id: UUID | None
) -> UUID:
    """The member a swipe, vote, or RSVP is written for.

    That is the caller. Only the owner may write for a guest. Any other
    `member_id` is 403.
    """
    if member_id is None or member_id == seat.member_id:
        return seat.member_id
    if seat.owner and await c.fetchval(GUEST, member_id, group_id) is not None:
        return member_id
    raise Forbidden()


async def post_system(
    c: asyncpg.Connection,
    group_id: UUID,
    code: str,
    args: dict[str, Any],
    night_id: UUID | None = None,
    subject: UUID | None = None,
) -> None:
    """A system message: the phone writes its text in its own language from code + args.

    `subject` is the user it is about. Deleting that account deletes the message.
    """
    await c.execute(SYSTEM_MESSAGE, group_id, code, args, night_id, subject)
