"""Phase 5: chat, wrap-up, send a film."""

from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import Field, StringConstraints

from app.schemas.common import Base, Film, FilmId, Time, text
from app.schemas.phase1 import Card


class Message(Base):
    id: int
    kind: Literal["text", "system"]
    sender: Card | None
    body: str | None
    code: str | None
    args: dict[str, Any] | None
    film_id: str | None
    film: Film | None
    night_id: UUID | None
    created_at: Time


class MessageList(Base):
    items: list[Message]
    has_more: bool


class MessagePost(Base):
    body: text(1000, multiline=True)
    film_id: FilmId | None = None
    film: Film | None = None
    night_id: UUID | None = None


class WrapupPost(Base):
    seat_row: Annotated[str, StringConstraints(pattern=r"^[A-Z]$")] | None = None
    first_seat: int | None = Field(default=None, ge=1, le=99)
    member_ids: list[UUID] | None = Field(default=None, max_length=60)


class WrapupResult(Base):
    created: int
    skipped: int


class SendFilm(Base):
    user_id: UUID
    film_id: FilmId
    film: Film
    note: text(140, min_len=0) | None = None
