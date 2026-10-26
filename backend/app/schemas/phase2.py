"""Phase 2: friends, profiles, feed, reactions, blocks, reports.

No model here has a field that can hold a diary date. A test checks this.
"""

from typing import Annotated, Literal
from uuid import UUID

from pydantic import Field, StringConstraints

from app.schemas.common import Base, Film, FilmId, text
from app.schemas.phase1 import Card

Relation = Literal["none", "friend", "incoming", "outgoing"]


class Lookup(Base):
    card: Card
    relation: Relation


class FriendRequestPost(Base):
    user_id: UUID


class FriendRequestResult(Base):
    status: Literal["pending", "friends"]


class FriendRequests(Base):
    incoming: list[Card]
    outgoing: list[Card]


class Match(Base):
    both: int
    pct: int | None


class FriendItem(Base):
    card: Card
    visible: bool
    match: Match | None


class FriendList(Base):
    items: list[FriendItem]


class Stats(Base):
    films: int
    viewings: int
    avg_rating: float | None
    top_genres: list[str]
    top_langs: list[str]


class TopFilm(Base):
    film_id: str
    film: Film
    rating: float | None


class WatchItem(Base):
    film_id: str
    film: Film


class ProfileView(Base):
    card: Card
    relation: Literal["self", "friend"]
    visible: bool
    match: Match | None
    stats: Stats | None
    top_films: list[TopFilm]
    watchlist: list[WatchItem]


class ShelfItem(Base):
    film_id: str
    film: Film
    rating: float | None
    viewings: int


class Shelf(Base):
    items: list[ShelfItem]
    next_cursor: str | None


class Watcher(Base):
    user: Card
    rating: float | None


class FriendsWhoWatched(Base):
    items: list[Watcher]


class FeedItem(Base):
    id: str
    kind: Literal["watched", "reaction", "sent"]
    user: Card
    film_id: str
    film: Film
    rating: float | None
    reaction: int | None
    note: str | None
    my_reaction: int | None


class Feed(Base):
    items: list[FeedItem]
    next_cursor: str | None


class ReactionPut(Base):
    user_id: UUID
    film_id: FilmId
    reaction: int | None = Field(ge=0, le=7)


class BlockPost(Base):
    user_id: UUID


class BlockList(Base):
    items: list[Card]


class ReportPost(Base):
    kind: Literal["user", "message", "group"]
    target_id: Annotated[str, StringConstraints(min_length=1, max_length=64)]
    reason: Literal["spam", "abuse", "harassment", "inappropriate", "other"]
    note: text(500, min_len=0, multiline=True) | None = None


class ReportResult(Base):
    id: UUID
