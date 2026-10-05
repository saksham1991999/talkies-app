"""Night wrap-up: one stub per account member who went."""

import random
import string
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from uuid import UUID


@dataclass(frozen=True)
class Attendee:
    """Someone who went. `user_id` is None for a guest, who gets no stub."""

    name: str
    user_id: UUID | None = None


@dataclass(frozen=True)
class StubPlan:
    user_id: UUID
    stub_id: str
    seat: str
    company: str | None
    local_date: date


def local_date(starts_at: datetime, tz_offset_min: int) -> date:
    """The calendar day on the group's clock."""
    return (starts_at.astimezone(UTC) + timedelta(minutes=tz_offset_min)).date()


def company_name(name: str) -> str:
    """A name as it goes into "who you went with": no commas, no edge spaces."""
    return name.replace(",", "").strip()


def plan_wrapup(
    night_id: UUID,
    starts_at: datetime,
    tz_offset_min: int,
    attendees: list[Attendee],
    rng: random.Random,
    seat_row: str | None = None,
    first_seat: int | None = None,
) -> list[StubPlan]:
    """Plan the stubs. `attendees` are in member order.

    Every stub has the same row letter. Seats run along it in member order from
    `first_seat`. "With" is the other attendees' names, guests included.
    """
    row = seat_row or rng.choice(string.ascii_uppercase)
    start = first_seat if first_seat is not None else rng.randint(1, 20)
    day = local_date(starts_at, tz_offset_min)
    owners = [(a.user_id, a) for a in attendees if a.user_id is not None]
    plans = []
    for seat_index, (user_id, who) in enumerate(owners):
        others = [company_name(a.name) for a in attendees if a is not who]
        company = ", ".join(n for n in others if n) or None
        seat = f"{row}{start + seat_index}"
        plans.append(StubPlan(user_id, f"night-{night_id}", seat, company, day))
    return plans
