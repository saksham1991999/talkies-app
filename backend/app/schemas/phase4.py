"""Phase 4: movie nights."""

from typing import Literal
from uuid import UUID

from pydantic import Field

from app.schemas.common import Base, Film, FilmId, Time, text

Answer = Literal["yes", "no", "maybe"]


class NightOption(Base):
    id: UUID
    kind: Literal["film", "slot"]
    position: int
    film_id: str | None
    film: Film | None
    starts_at: Time | None
    approvals: int


class NightEvent(Base):
    film_id: str
    film: Film
    starts_at: Time
    tz_offset_min: int
    place: str | None


class NightRsvp(Base):
    member_id: UUID
    response: Answer


class Night(Base):
    id: UUID
    group_id: UUID
    status: Literal["poll", "set", "done"]
    host_id: UUID | None
    tz_offset_min: int
    place: str | None
    options: list[NightOption]
    mine: list[UUID]
    event: NightEvent | None
    rsvps: list[NightRsvp]


class NightList(Base):
    items: list[Night]


class NightFilm(Base):
    film_id: FilmId
    film: Film


class NightCreate(Base):
    films: list[NightFilm] = Field(min_length=1, max_length=3)
    slots: list[Time] = Field(min_length=1, max_length=2)
    tz_offset_min: int = Field(ge=-840, le=840)
    place: text(80) | None = None


class VotesPut(Base):
    option_ids: list[UUID] = Field(max_length=6)
    member_id: UUID | None = None


class VotesResult(Base):
    approvals: dict[str, int]


class ClosePost(Base):
    film_option_id: UUID | None = None
    slot_option_id: UUID | None = None
    place: text(80) | None = None


class RsvpPut(Base):
    response: Answer
    member_id: UUID | None = None
