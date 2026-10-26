"""Building blocks for the models in backend/API.md."""

from datetime import datetime
from typing import Annotated, Any

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    PlainSerializer,
    StringConstraints,
)

from app.logic.validate import check_text, format_time, parse_time


class Base(BaseModel):
    """Every model rejects unknown keys."""

    model_config = ConfigDict(extra="forbid")


class Empty(Base):
    """The reply `{}`."""


# UTC time on the wire: 2026-10-01T12:00:00.000Z. Input without a zone is refused.
Time = Annotated[
    datetime, BeforeValidator(parse_time), PlainSerializer(format_time, return_type=str)
]

# The app's compact film JSON. The server keeps only the known keys (see clean_film).
Film = dict[str, Any]

FilmId = Annotated[str, StringConstraints(pattern=r"^Q[0-9]{1,12}$")]


def _line(value: str) -> str:
    return check_text(value)


def _lines(value: str) -> str:
    return check_text(value, multiline=True)


def text(max_len: int, min_len: int = 1, multiline: bool = False):
    """A trimmed string of bounded length, without NUL or control characters."""
    return Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=min_len, max_length=max_len),
        AfterValidator(_lines if multiline else _line),
    ]


def _lower(value: Any) -> Any:
    return value.strip().lower() if isinstance(value, str) else value


Handle = Annotated[str, BeforeValidator(_lower), StringConstraints(pattern=r"^[a-z0-9_]{3,20}$")]
Email = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        to_lower=True,
        min_length=3,
        max_length=254,
        pattern=r"^[^@\s]+@[^@\s]+$",
    ),
    # The pattern only rules out `@` and whitespace, so NUL and other control
    # characters would pass through to Supabase Auth.
    AfterValidator(_line),
]
