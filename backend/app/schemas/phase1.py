"""Phase 1: login, profile, sync."""

from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import Field, StringConstraints, model_validator

from app.schemas.common import Base, Email, Film, Handle, Time, text

SyncKind = Literal["stub", "wish", "meta", "taste"]
Visibility = Literal["private", "friends"]


class Card(Base):
    id: UUID
    handle: str | None
    display_name: str | None
    avatar_color: int


class SessionUser(Base):
    id: UUID


class Session(Base):
    access_token: str
    refresh_token: str
    expires_at: int
    user: SessionUser


class Health(Base):
    ok: bool
    api: Literal[1]
    auth: list[Literal["email", "google", "apple"]]


class ErrorBody(Base):
    code: str
    message: str
    detail: Any = None


class Error(Base):
    error: ErrorBody


class OtpRequest(Base):
    email: Email


class VerifyRequest(Base):
    email: Email
    code: Annotated[str, StringConstraints(strip_whitespace=True, pattern=r"^[0-9]{4,10}$")]


class RefreshRequest(Base):
    refresh_token: Annotated[str, StringConstraints(min_length=1, max_length=2048)]


class IdTokenRequest(Base):
    provider: Literal["google", "apple"]
    id_token: Annotated[str, StringConstraints(min_length=1, max_length=8192)]
    access_token: Annotated[str, StringConstraints(max_length=8192)] | None = None
    nonce: Annotated[str, StringConstraints(max_length=512)] | None = None
    # Apple only: the authorization code from the same sign-in. The backend
    # trades it with Apple for a refresh token, so the grant can be revoked on
    # account deletion (App Store rule 4.8).
    authorization_code: Annotated[str, StringConstraints(max_length=8192)] | None = None


class Me(Base):
    id: UUID
    handle: str | None
    display_name: str | None
    avatar_color: int
    visibility: Visibility
    share_ratings: bool


class MePatch(Base):
    """Any of the fields. A field that is left out stays as it is."""

    handle: Handle | None = None
    display_name: text(30) | None = None
    avatar_color: int | None = Field(default=None, ge=0, le=10)
    visibility: Visibility | None = None
    share_ratings: bool | None = None

    @model_validator(mode="after")
    def _only_names_may_be_null(self) -> "MePatch":
        for name in ("avatar_color", "visibility", "share_ratings"):
            if name in self.model_fields_set and getattr(self, name) is None:
                raise ValueError(f"{name} cannot be null")
        return self


class SyncRecord(Base):
    kind: SyncKind
    id: Annotated[str, StringConstraints(min_length=1, max_length=64)]
    updated_at: Time
    deleted: bool = False
    film: Film | None = None
    data: dict[str, Any] = Field(default_factory=dict)


class SyncRecordSeq(SyncRecord):
    seq: int


class SyncPush(Base):
    # The batch limit (200) is checked in the route: it answers 413, not 422.
    records: list[SyncRecord]


class Rejected(Base):
    kind: SyncKind
    id: str
    code: Literal["invalid_record", "too_large", "limit_reached"]


class SyncPushResult(Base):
    server_time: Time
    conflicts: list[SyncRecordSeq]
    rejected: list[Rejected]


class SyncPull(Base):
    server_time: Time
    records: list[SyncRecordSeq]
    cursor: int
    more: bool
