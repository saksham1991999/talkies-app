"""Small helpers that several routers share."""

import zlib
from typing import Any
from uuid import UUID

import asyncpg

from app.errors import Invalid, TooLarge, Unauthorized
from app.logic.validate import RecordError, clean_film


def card(row: Any, prefix: str = "") -> dict:
    """A `card` from a row. `prefix` is for rows that hold two cards."""
    return {
        "id": row[f"{prefix}id"],
        "handle": row[f"{prefix}handle"],
        "display_name": row[f"{prefix}display_name"],
        "avatar_color": row[f"{prefix}avatar_color"],
    }


def user_color(user_id: UUID) -> int:
    """The avatar color a new profile starts with (0 to 10)."""
    return user_id.int % 11


def guest_color(name: str) -> int:
    return zlib.crc32(name.lower().encode()) % 11


async def ensure_profile(c: asyncpg.Connection, user_id: UUID) -> None:
    """Create the profile row on first use. 401 if the account is gone."""
    try:
        await c.execute(
            "insert into profiles (id, avatar_color) values ($1, $2) on conflict (id) do nothing",
            user_id,
            user_color(user_id),
        )
    except asyncpg.ForeignKeyViolationError as exc:
        # The Supabase user was deleted while the access token is still valid.
        raise Unauthorized("account_deleted", "This account was deleted") from exc


def film_or_error(film: Any, film_id: str | None = None) -> dict:
    """The clean snapshot of a film from a request. 422 or 413 when it is not one."""
    try:
        return clean_film(film, film_id)
    except RecordError as exc:
        raise (TooLarge() if exc.code == "too_large" else Invalid()) from exc
