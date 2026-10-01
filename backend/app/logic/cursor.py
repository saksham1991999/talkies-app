"""Opaque list cursors: a number in base64url, not signed.

The same form serves both kinds: a feed cursor holds the last `feed_seq`, a
shelf cursor holds an offset.
"""

import base64
import binascii

_URL_TO_STANDARD = str.maketrans("-_", "+/")


class BadCursor(ValueError):
    pass


def encode_cursor(number: int) -> str:
    return base64.urlsafe_b64encode(str(number).encode("ascii")).decode("ascii").rstrip("=")


def decode_cursor(text: str | None) -> int | None:
    """Return the number, or None when there is no cursor. Raise BadCursor."""
    if not text:
        return None
    try:
        padded = text.translate(_URL_TO_STANDARD) + "=" * (-len(text) % 4)
        raw = base64.b64decode(padded, validate=True)  # validate: no stray characters
    except (binascii.Error, ValueError) as exc:
        raise BadCursor() from exc
    if not raw.isdigit() or len(raw) > 18:
        raise BadCursor()
    return int(raw)
