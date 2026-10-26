"""Checks for data that comes from phones. Pure functions, no I/O.

Rules from backend/API.md: times are UTC with Z, film snapshots are small and
have no `file:` poster, and sync records follow the phone's own JSON.
"""

import json
import math
import re
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

QID_RE = re.compile(r"^Q[0-9]{1,12}$")
WIRE_FILM_RE = re.compile(r"^(Q[0-9]{1,12}|my:[A-Za-z0-9_.-]{1,40})$")
HANDLE_RE = re.compile(r"^[a-z0-9_]{3,20}$")
INVITE_RE = re.compile(r"^[A-HJ-KM-NP-Z2-9]{8}$")
# Exactly three fraction digits: the wire format is millisecond precision, and
# a finer value would come back truncated, so a sync record could never
# round-trip and a retry would look like a conflict.
_TIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$")
_DAY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

FILM_MAX = 4096
STUB_DATA_MAX = 16 * 1024
WISH_DATA_MAX = 2 * 1024
META_MAX = 64 * 1024
TASTE_MAX = 24 * 1024
CLOCK_SKEW = timedelta(minutes=5)
FEED_FRESH_DAYS = 14

SYNC_KINDS = ("stub", "wish", "meta", "taste")
_PRECISIONS = ("day", "month", "year", "none")
_MAX_DEPTH = 8


class RecordError(ValueError):
    """A record the server will not store. `code` is the `rejected.code`."""

    def __init__(self, code: str = "invalid_record"):
        super().__init__(code)
        self.code = code


# ---------------------------------------------------------------------------
# Times


def parse_time(value: Any) -> datetime:
    """UTC ISO-8601 that ends in Z. A time without Z (naive, or with an offset) is an error.

    A datetime object (a database value) passes when it has a zone.
    """
    if isinstance(value, datetime):
        if value.tzinfo is None:
            raise ValueError("time must have a zone")
        return value.astimezone(UTC)
    if not isinstance(value, str) or not _TIME_RE.fullmatch(value):
        raise ValueError("time must be ISO-8601 with Z")
    try:
        return datetime.fromisoformat(value).astimezone(UTC)
    except (ValueError, OverflowError) as exc:
        raise ValueError("time is not valid") from exc


def format_time(value: datetime) -> str:
    """2026-10-01T12:00:00.000Z"""
    value = value.astimezone(UTC)
    return value.strftime("%Y-%m-%dT%H:%M:%S.") + f"{value.microsecond // 1000:03d}Z"


# ---------------------------------------------------------------------------
# Text and JSON


def check_text(text: str, multiline: bool = False) -> str:
    """Reject NUL, other control characters, and text that is not valid UTF-8."""
    try:
        text.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise ValueError("text is not valid") from exc
    allowed = "\n\t" if multiline else ""
    if any((ch < " " and ch not in allowed) or ch == "\x7f" for ch in text):
        raise ValueError("text has a control character")
    return text


def json_size(value: Any) -> int:
    """Bytes of the JSON as Postgres prints jsonb (", " and ": " separators)."""
    return len(json.dumps(value, ensure_ascii=False).encode("utf-8", "surrogatepass"))


def _walk(value: Any, depth: int = 0) -> None:
    """Raise when a JSON value is nested too deep or holds NUL or a lone surrogate."""
    if depth > _MAX_DEPTH:
        raise RecordError()
    if isinstance(value, str):
        _text_or_record_error(value)
    elif isinstance(value, dict):
        for key, item in value.items():
            _text_or_record_error(key)
            _walk(item, depth + 1)
    elif isinstance(value, list):
        for item in value:
            _walk(item, depth + 1)
    elif isinstance(value, float):
        if not math.isfinite(value):
            raise RecordError()
    elif not (value is None or isinstance(value, bool | int)):
        raise RecordError()


def _text_or_record_error(text: str) -> None:
    try:
        text.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise RecordError() from exc
    if "\x00" in text:
        raise RecordError()


# ---------------------------------------------------------------------------
# Film snapshot


def _str(value: Any, max_len: int) -> str:
    if not isinstance(value, str) or len(value) > max_len:
        raise RecordError()
    return value


def _int(value: Any, low: int, high: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise RecordError()
    return value


def _str_list(value: Any, max_items: int = 60, max_len: int = 120) -> list[str]:
    if not isinstance(value, list) or len(value) > max_items:
        raise RecordError()
    return [_str(item, max_len) for item in value]


def clean_film(film: Any, film_id: str | None = None) -> dict:
    """Keep the known keys of the app's compact film JSON, with their types.

    Unknown keys are dropped, so a snapshot can never carry diary data. A
    `file:` poster is an error. With `film_id`, the snapshot must be that film.
    """
    if not isinstance(film, dict):
        raise RecordError()
    _walk(film)
    if json_size(film) > FILM_MAX:
        raise RecordError("too_large")
    out: dict[str, Any] = {}
    out["id"] = _str(film.get("id"), 64)
    if not WIRE_FILM_RE.fullmatch(out["id"]):
        raise RecordError()
    if film_id is not None and out["id"] != film_id:
        raise RecordError()
    out["t"] = _str(film.get("t"), 300)
    if not out["t"]:
        raise RecordError()
    for key in ("o", "w"):
        if film.get(key) is not None:
            out[key] = _str(film[key], 300)
    if film.get("d") is not None:
        out["d"] = _str(film["d"], 10)
    if film.get("p") is not None:
        out["p"] = _str(film["p"], 300)
        if out["p"].startswith("file:"):
            raise RecordError()
    if film.get("k") is not None:
        if film["k"] != "s":
            raise RecordError()
        out["k"] = "s"
    for key, high in (("y", 3000), ("rt", 5000), ("pop", 10**9), ("sn", 1000)):
        if film.get(key) is not None:
            out[key] = _int(film[key], 0, high)
    for key in ("dir", "cast", "g", "l", "c", "ott"):
        if film.get(key) is not None:
            out[key] = _str_list(film[key])
    return out


# ---------------------------------------------------------------------------
# Sync records


@dataclass(frozen=True)
class Row:
    """A sync record checked and ready to store, with the derived columns."""

    kind: str
    id: str
    updated_at: datetime
    deleted: bool
    film: dict | None
    data: dict
    film_id: str | None = None
    rating: float | None = None
    private: bool = False
    watched_on: date | None = None
    fresh: bool = False


def _day(value: Any) -> date:
    if not isinstance(value, str) or not _DAY_RE.fullmatch(value):
        raise RecordError()
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise RecordError() from exc


def _rating(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise RecordError()
    if not 0.1 <= value <= 5.0:
        raise RecordError()
    return float(value)


def is_fresh(watched: date, now: datetime) -> bool:
    """A viewing that may enter feeds: within 14 days, a day ahead allowed for time zones."""
    today = now.date()
    return today - timedelta(days=FEED_FRESH_DAYS) <= watched <= today + timedelta(days=1)


def _stub_row(rid: str, updated: datetime, film: Any, data: dict, now: datetime) -> Row:
    if data.get("id", rid) != rid:
        raise RecordError()
    film_id = data.get("film")
    if not isinstance(film_id, str) or not WIRE_FILM_RE.fullmatch(film_id):
        raise RecordError()
    private = data.get("priv", False)
    if not isinstance(private, bool):
        raise RecordError()
    precision = data.get("prec", "day")
    if precision not in _PRECISIONS:
        raise RecordError()
    watched = _day(data["date"]) if precision == "day" and data.get("date") is not None else None
    fresh = not private and watched is not None and is_fresh(watched, now)
    return Row(
        "stub",
        rid,
        updated,
        False,
        # The snapshot must be the film the record names, not whatever the
        # client sent alongside it.
        clean_film(film, film_id),
        data,
        film_id=film_id,
        rating=_rating(data.get("rating")),
        private=private,
        watched_on=watched,
        fresh=fresh,
    )


def _meta_ok(data: dict) -> None:
    tags, venues, hidden = data.get("tags", []), data.get("venues", []), data.get("hidden", [])
    _str_list(tags, 1000, 100)
    _str_list(hidden, 20000, 64)
    if not isinstance(venues, list) or len(venues) > 1000:
        raise RecordError()
    for venue in venues:
        if not isinstance(venue, dict):
            raise RecordError()
        _str(venue.get("name"), 100)
        _str(venue.get("type"), 20)


def validate_record(
    kind: str,
    rid: str,
    updated_at: datetime,
    deleted: bool,
    film: Any,
    data: Any,
    now: datetime,
) -> Row:
    """Check one pushed record. Raise RecordError (`invalid_record`, `too_large`).

    `updated_at` is clamped to now + 5 minutes. A tombstone keeps nothing but
    its time: its film and data are dropped.
    """
    updated = min(updated_at, now + CLOCK_SKEW)
    if kind not in SYNC_KINDS:
        raise RecordError()
    _check_id(kind, rid)
    if deleted:
        film_id = rid if kind == "wish" else None
        return Row(kind, rid, updated, True, None, {}, film_id=film_id)
    if not isinstance(data, dict):
        raise RecordError()
    limits = {"stub": STUB_DATA_MAX, "wish": WISH_DATA_MAX, "meta": META_MAX, "taste": TASTE_MAX}
    _walk(data)
    if json_size(data) > limits[kind]:
        raise RecordError("too_large")
    if kind == "stub":
        return _stub_row(rid, updated, film, data, now)
    if kind == "wish":
        if data.get("film", rid) != rid:
            raise RecordError()
        # A wish is keyed by its film id, so the snapshot must be that film.
        return Row(kind, rid, updated, False, clean_film(film, rid), data, film_id=rid)
    if kind == "meta":
        _meta_ok(data)
    elif not isinstance(data.get("v"), int):
        raise RecordError()
    return Row(kind, rid, updated, False, None, data)


def _check_id(kind: str, rid: str) -> None:
    if kind == "stub":
        if not 1 <= len(rid) <= 64:
            raise RecordError()
        _text_or_record_error(rid)
        if any(ch < " " or ch == "\x7f" for ch in rid):
            raise RecordError()
    elif kind == "wish":
        if not WIRE_FILM_RE.fullmatch(rid):
            raise RecordError()
    elif rid != kind:
        raise RecordError()
