"""Limits and shapes of the request models."""

import re
import typing
from datetime import date, datetime
from uuid import uuid4

import pytest
from pydantic import BaseModel, ValidationError

from app.schemas import MODELS
from app.schemas.phase1 import IdTokenRequest, MePatch, OtpRequest, SyncRecord, VerifyRequest
from app.schemas.phase2 import FeedItem, ReactionPut, ReportPost
from app.schemas.phase3 import DeckPut, GroupCreate, GuestPost, SwipesPut
from app.schemas.phase4 import NightCreate, VotesPut
from app.schemas.phase5 import MessagePost, SendFilm, WrapupPost

FILM = {"id": "Q1", "t": "T"}
UUID = str(uuid4())


def bad(model, **fields):
    with pytest.raises(ValidationError):
        model(**fields)


def test_reaction_range():
    for ok in (0, 3, 7, None):
        assert ReactionPut(user_id=UUID, film_id="Q1", reaction=ok).reaction == ok
    for no in (-1, 8, "x"):
        bad(ReactionPut, user_id=UUID, film_id="Q1", reaction=no)
    bad(ReactionPut, user_id=UUID, film_id="Q1")  # null clears, but the key must be there
    bad(ReactionPut, user_id=UUID, film_id="my:dev.1", reaction=1)  # QID films only


def test_me_patch():
    patch = MePatch.model_validate({"handle": " ASHA_r ", "display_name": "  Asha  "})
    assert (patch.handle, patch.display_name) == ("asha_r", "Asha")
    assert patch.model_fields_set == {"handle", "display_name"}
    assert MePatch.model_validate({"display_name": None, "handle": None}).display_name is None
    for field, value in [
        ("visibility", None),
        ("share_ratings", None),
        ("avatar_color", None),
        ("avatar_color", 11),
        ("avatar_color", -1),
        ("visibility", "public"),
        ("handle", "ab"),
        ("handle", "a" * 21),
        ("handle", "no spaces"),
        ("handle", "dash-ed"),
        ("display_name", "x" * 31),
        ("display_name", ""),
        ("display_name", "a\nb"),
        ("display_name", "a\x00b"),
        ("surprise", 1),
    ]:
        with pytest.raises(ValidationError):
            MePatch.model_validate({field: value})


def test_email_and_code():
    assert OtpRequest(email=" A@B.test ").email == "a@b.test"
    bad(OtpRequest, email="no-at-sign")
    bad(OtpRequest, email="a b@c.test")
    bad(OtpRequest, email="a@" + "b" * 260)
    # NUL and other control characters are not `@` or whitespace, so the pattern
    # alone would let them through to Supabase Auth.
    bad(OtpRequest, email="a\x00b@c.test")
    bad(OtpRequest, email="a\tb@c.test")
    bad(OtpRequest, email="a\x7fb@c.test")
    assert VerifyRequest(email="a@b.test", code=" 123456 ").code == "123456"
    bad(VerifyRequest, email="a@b.test", code="12a456")
    bad(VerifyRequest, email="a@b.test", code="123")


def test_id_token_request():
    assert IdTokenRequest(provider="google", id_token="t").nonce is None
    bad(IdTokenRequest, provider="facebook", id_token="t")
    bad(IdTokenRequest, provider="google", id_token="")


def test_times_must_have_a_zone():
    base = {"kind": "stub", "id": "s", "deleted": False, "film": None, "data": {}}
    ok = SyncRecord.model_validate({**base, "updated_at": "2026-10-01T12:00:00Z"})
    assert ok.updated_at.tzinfo is not None
    for text in ("2026-10-01T12:00:00", "2026-10-01", 1790856000, None, "now"):
        with pytest.raises(ValidationError):
            SyncRecord.model_validate({**base, "updated_at": text})
    bad(SyncRecord, kind="memo", id="s", updated_at="2026-10-01T12:00:00Z")
    bad(SyncRecord, kind="stub", id="", updated_at="2026-10-01T12:00:00Z")
    bad(SyncRecord, kind="stub", id="x" * 65, updated_at="2026-10-01T12:00:00Z")


def test_counts_and_sizes():
    film = {"film_id": "Q1", "film": FILM}
    bad(DeckPut, base_version=-1, items=[])
    bad(DeckPut, base_version=0, items=[film] * 121)
    DeckPut(base_version=0, items=[])
    bad(SwipesPut, swipes=[])
    swipe = {"film_id": "Q1", "vote": "want"}
    SwipesPut(swipes=[swipe] * 50)
    bad(SwipesPut, swipes=[swipe] * 51)
    bad(SwipesPut, swipes=[{"film_id": "Q1", "vote": "maybe"}])
    slot = "2026-10-03T14:30:00Z"
    NightCreate(films=[film], slots=[slot, slot], tz_offset_min=330, place=None)
    bad(NightCreate, films=[], slots=[slot], tz_offset_min=0)
    bad(NightCreate, films=[film] * 4, slots=[slot], tz_offset_min=0)
    bad(NightCreate, films=[film], slots=[slot] * 3, tz_offset_min=0)
    bad(NightCreate, films=[film], slots=[slot], tz_offset_min=841)
    bad(NightCreate, films=[film], slots=[slot], tz_offset_min=0, place="x" * 81)
    bad(VotesPut, option_ids=[UUID] * 7)


def test_names_and_text():
    assert GroupCreate(name=" Friday Crew ").name == "Friday Crew"
    bad(GroupCreate, name="")
    bad(GroupCreate, name="   ")
    bad(GroupCreate, name="x" * 41)
    bad(GroupCreate, name="a\nb")
    bad(GuestPost, name="x" * 41)
    assert MessagePost(body="Hello\nthere").body == "Hello\nthere"
    bad(MessagePost, body="   ")
    bad(MessagePost, body="x" * 1001)
    bad(MessagePost, body="a\x00b")
    assert ReportPost(kind="user", target_id="x", reason="spam").note is None
    bad(ReportPost, kind="user", target_id="x", reason="spam", note="n" * 501)
    bad(ReportPost, kind="user", target_id="x", reason="rude")
    bad(SendFilm, user_id=UUID, film_id="Q1", film=FILM, note="n" * 141)
    SendFilm(user_id=UUID, film_id="Q1", film=FILM, note=None)


def test_wrapup_post():
    WrapupPost()
    WrapupPost(seat_row="Z", first_seat=99, member_ids=[UUID])
    for fields in ({"seat_row": "AB"}, {"seat_row": "a"}, {"first_seat": 0}, {"first_seat": 100}):
        bad(WrapupPost, **fields)


def test_message_post_film_pair_is_checked_by_the_route_not_the_model():
    # The model allows either alone. The route answers 422 when only one is sent.
    assert MessagePost(body="x", film_id="Q1").film is None


def _has_date_type(annotation) -> bool:
    if annotation in (datetime, date):
        return True
    if isinstance(annotation, type) and issubclass(annotation, BaseModel):
        return any(_has_date_type(f.annotation) for f in annotation.model_fields.values())
    return any(_has_date_type(arg) for arg in typing.get_args(annotation))


def test_feed_item_has_no_date():
    assert not _has_date_type(FeedItem)


def test_models_forbid_extra_keys():
    for name, cls in MODELS.items():
        assert cls.model_config.get("extra") == "forbid", name
    assert re.fullmatch(r"[a-z_]+", "".join(MODELS))
