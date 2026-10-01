"""Phase 3: groups, shared list, deck, swipes."""

from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import Field, StringConstraints

from app.schemas.common import Base, Film, FilmId, text

Vote = Literal["want", "skip", "seen"]


class Member(Base):
    id: UUID
    name: str
    avatar_color: int
    handle: str | None
    guest: bool
    owner: bool
    me: bool


class Group(Base):
    id: UUID
    name: str
    invite_code: str
    deck_version: int
    member_count: int


class GroupList(Base):
    items: list[Group]


class GroupDetail(Group):
    members: list[Member]


class GroupCreate(Base):
    name: text(40)


class GroupPatch(Base):
    name: text(40)


class InviteCode(Base):
    invite_code: str


class JoinPost(Base):
    code: Annotated[str, StringConstraints(min_length=1, max_length=32)]


class GuestPost(Base):
    name: text(40)


class FilmEntry(Base):
    film_id: str
    film: Film


class GroupFilms(Base):
    items: list[FilmEntry]


class GroupFilmPut(Base):
    film: Film


class DeckItem(Base):
    film_id: str
    film: Film
    seen_by: int


class Deck(Base):
    version: int
    items: list[DeckItem]


class DeckPutItem(Base):
    film_id: FilmId
    film: Film


class DeckPut(Base):
    base_version: int = Field(ge=0)
    items: list[DeckPutItem] = Field(max_length=120)


class DeckPutResult(Base):
    version: int


class WantedItem(Base):
    film_id: str
    film: Film
    n: int


class DeckInputs(Base):
    tastes: list[dict[str, Any]]
    seen: list[str]
    wanted: list[WantedItem]


class SwipeIn(Base):
    film_id: FilmId
    vote: Vote
    member_id: UUID | None = None


class SwipesPut(Base):
    swipes: list[SwipeIn] = Field(min_length=1, max_length=50)


class SwipesResult(Base):
    saved: int


class TallyCounts(Base):
    want: int
    skip: int
    seen: int


class Tallies(Base):
    tallies: dict[str, TallyCounts]
    mine: dict[str, Vote]
