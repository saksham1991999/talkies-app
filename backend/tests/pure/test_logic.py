"""Match, wrap-up, cursors, record checks, and the limiter."""

import logging
import random
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import pytest
from starlette.requests import Request

from app.errors import RateLimited
from app.logic.cursor import BadCursor, decode_cursor, encode_cursor
from app.logic.match import Match, match_score
from app.logic.validate import (
    RecordError,
    check_text,
    clean_film,
    format_time,
    parse_time,
    validate_record,
)
from app.logic.wrapup import Attendee, local_date, plan_wrapup
from app.ratelimit import RULES, Limiter, client_ip
from tests.helpers import FakeClock

KANTARA = {
    "id": "Q949228",
    "t": "Kantara",
    "y": 2022,
    "d": "2022-09-30",
    "g": ["action", "drama"],
    "l": ["kn"],
    "c": ["IN"],
    "dir": ["Rishab Shetty"],
    "cast": ["Rishab Shetty", "Sapthami Gowda"],
    "p": "en/a/a5/Kantara_film_poster.jpg",
    "pop": 61,
}
NOW = datetime(2026, 10, 1, 12, 0, tzinfo=UTC)


# --- match ------------------------------------------------------------------


def _shelves(rng: random.Random) -> tuple[int, int, list[tuple[float | None, float | None]]]:
    n_mine, n_theirs = rng.randint(1, 80), rng.randint(1, 80)
    shared = rng.randint(0, min(n_mine, n_theirs))
    rate = lambda: rng.choice([None, round(rng.uniform(0.1, 5.0), 1)])  # noqa: E731
    return n_mine, n_theirs, [(rate(), rate()) for _ in range(shared)]


def test_match_no_overlap_is_none():
    assert match_score(10, 10, [], True) == Match(0, None)
    assert match_score(0, 0, [], False) == Match(0, None)


def test_match_known_values():
    # One shared film of 5 and 5: coverage 1/8. Same rating: harmony 1.
    assert match_score(5, 5, [(4.0, 4.0)], True) == Match(1, round(100 / 8))
    # Opposite ends of the scale: d = 4.9/4.9 = 1, harmony = 1 - 0.6/3 = 0.8.
    assert match_score(5, 5, [(0.1, 5.0)], True) == Match(1, round(100 / 8 * 0.8))


def test_match_range_and_symmetry():
    rng = random.Random(7)
    for _ in range(500):
        n_mine, n_theirs, common = _shelves(rng)
        result = match_score(n_mine, n_theirs, common, True)
        if not common:
            assert result.pct is None
            continue
        assert result.both == len(common)
        assert result.pct is not None
        assert 0 <= result.pct < 100
        swapped = [(b, a) for a, b in common]
        assert match_score(n_theirs, n_mine, swapped, True) == result


def test_match_ignores_ratings_when_told_to():
    rng = random.Random(11)
    for _ in range(300):
        n_mine, n_theirs, common = _shelves(rng)
        base = match_score(n_mine, n_theirs, common, False)
        changed = [(a, None if b is None else round(rng.uniform(0.1, 5.0), 1)) for a, b in common]
        unrated = [(a, None) for a, _ in common]
        assert match_score(n_mine, n_theirs, changed, False) == base
        assert match_score(n_mine, n_theirs, unrated, False) == base
        assert match_score(n_mine, n_theirs, unrated, True) == base


def test_more_disagreement_never_raises_the_score():
    rng = random.Random(3)

    def farthest(mine: float) -> float:
        return 5.0 if mine < 2.55 else 0.1

    for _ in range(300):
        n = rng.randint(1, 60)
        mine = [round(rng.uniform(0.1, 5.0), 1) for _ in range(n)]
        theirs = [round(rng.uniform(0.1, 5.0), 1) for _ in range(n)]
        # Some friend ratings move to the far end of the scale: no pair gets closer.
        worse = [
            farthest(m) if rng.random() < 0.5 else t for m, t in zip(mine, theirs, strict=True)
        ]
        base = match_score(n, n, list(zip(mine, theirs, strict=True)), True)
        result = match_score(n, n, list(zip(mine, worse, strict=True)), True)
        assert result.pct <= base.pct


def test_more_shared_films_never_lower_coverage():
    scores = [match_score(20, 20, [(None, None)] * n, False).pct for n in range(1, 21)]
    assert scores == sorted(scores)


# --- wrap-up ----------------------------------------------------------------

NIGHT = UUID("11111111-1111-1111-1111-111111111111")
A, B, C = (UUID(int=i) for i in (1, 2, 3))


def test_wrapup_seats_company_id_and_date():
    people = [
        Attendee("Asha", A),
        Attendee("Ravi, Jr.", B),
        Attendee("Meena", None),
        Attendee("Dev", C),
    ]
    plans = plan_wrapup(
        NIGHT, datetime(2026, 10, 3, 20, 0, tzinfo=UTC), 330, people, random.Random(1), "F", 7
    )
    assert [p.user_id for p in plans] == [A, B, C]  # the guest gets no stub
    assert [p.seat for p in plans] == ["F7", "F8", "F9"]
    assert {p.stub_id for p in plans} == {f"night-{NIGHT}"}
    assert plans[0].company == "Ravi Jr., Meena, Dev"  # commas removed, guest included
    assert plans[1].company == "Asha, Meena, Dev"
    assert plans[0].local_date == date(2026, 10, 4)  # 20:00 UTC is 01:30 the next day at +05:30


def test_wrapup_random_row_and_seat_are_in_range_and_repeatable():
    people = [Attendee("A", A), Attendee("B", B)]
    start = datetime(2026, 10, 3, 20, 0, tzinfo=UTC)
    first = plan_wrapup(NIGHT, start, 0, people, random.Random(5))
    again = plan_wrapup(NIGHT, start, 0, people, random.Random(5))
    assert first == again
    row, number = first[0].seat[0], int(first[0].seat[1:])
    assert "A" <= row <= "Z"
    assert 1 <= number <= 20
    assert first[1].seat == f"{row}{number + 1}"


def test_wrapup_alone_has_no_company():
    plans = plan_wrapup(NIGHT, NOW, 0, [Attendee("Asha", A)], random.Random(1), "A", 1)
    assert plans[0].company is None


def test_local_date_follows_the_offset_both_ways():
    at = datetime(2026, 10, 3, 23, 0, tzinfo=UTC)
    assert local_date(at, 120) == date(2026, 10, 4)
    assert local_date(at, -300) == date(2026, 10, 3)


# --- cursors ----------------------------------------------------------------


@pytest.mark.parametrize("number", [0, 1, 812, 10**12])
def test_cursor_round_trip(number):
    assert decode_cursor(encode_cursor(number)) == number


def test_cursor_is_url_safe_and_unpadded():
    assert set(encode_cursor(123456789)) <= set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )


@pytest.mark.parametrize("text", ["!!!", "abc$", encode_cursor(1)[:-1] + "!", "LTE", "YWJj", "e30"])
def test_bad_cursors(text):
    with pytest.raises(BadCursor):
        decode_cursor(text)


def test_no_cursor():
    assert decode_cursor(None) is None
    assert decode_cursor("") is None


# --- times and text ---------------------------------------------------------


def test_times_need_a_zone_and_come_out_in_utc_with_ms():
    assert parse_time("2026-10-01T12:00:00.000Z") == NOW
    assert format_time(NOW) == "2026-10-01T12:00:00.000Z"
    assert format_time(NOW + timedelta(milliseconds=7)) == "2026-10-01T12:00:00.007Z"
    for bad in (
        "2026-10-01T17:30:00+05:30",
        "2026-10-01T12:00:00+00:00",
        "2026-10-01T12:00:00",
        "2026-10-01T12:00:00.000",
        "2026-10-01",
        1790856000,
        None,
        "yesterday",
    ):
        with pytest.raises(ValueError):
            parse_time(bad)
    with pytest.raises(ValueError):
        parse_time(datetime(2026, 10, 1, 12, 0))


def test_text_checks():
    assert check_text("Asha") == "Asha"
    assert check_text("a\nb", multiline=True) == "a\nb"
    for bad in ("a\x00b", "a\nb", "a\x7fb", "\ud800"):
        with pytest.raises(ValueError):
            check_text(bad)
    with pytest.raises(ValueError):
        check_text("a\x00b", multiline=True)


# --- film snapshots ---------------------------------------------------------


def test_clean_film_keeps_known_keys_only():
    film = {
        **KANTARA,
        "memo": "2026-09-01 secret",
        "created": "2026-09-01",
        "x": {"date": "2026-01-01"},
    }
    assert clean_film(film) == KANTARA
    assert clean_film(KANTARA, "Q949228") == KANTARA


@pytest.mark.parametrize(
    "film",
    [
        None,
        [],
        {"t": "No id"},
        {"id": "Q1"},
        {"id": "Q1", "t": ""},
        {"id": "x1", "t": "Bad id"},
        {"id": "Q1", "t": "T", "p": "file:posters/1.jpg"},
        {"id": "Q1", "t": "T", "y": "2022"},
        {"id": "Q1", "t": "T", "y": True},
        {"id": "Q1", "t": "T", "g": "drama"},
        {"id": "Q1", "t": "T", "g": [1]},
        {"id": "Q1", "t": "T", "k": "movie"},
        {"id": "Q1", "t": "T\x00"},
    ],
)
def test_clean_film_rejects(film):
    with pytest.raises(RecordError):
        clean_film(film)


def test_clean_film_size_and_expected_id():
    with pytest.raises(RecordError) as caught:
        clean_film({"id": "Q1", "t": "T", "cast": ["x" * 100] * 60})
    assert caught.value.code == "too_large"
    with pytest.raises(RecordError):
        clean_film(KANTARA, "Q1")
    assert clean_film({"id": "my:dev1.3", "t": "Mine"})["id"] == "my:dev1.3"


# --- sync records -----------------------------------------------------------

STUB = {
    "id": "s1",
    "no": 3,
    "film": "Q949228",
    "created": "2026-09-30T20:00:00.000",
    "date": "2026-09-30",
    "prec": "day",
    "rating": 4.5,
}


def check(kind="stub", rid="s1", deleted=False, film=KANTARA, data=None, at=NOW):
    data = STUB if data is None and kind == "stub" else (data or {})
    return validate_record(kind, rid, at, deleted, film, data, NOW)


def test_stub_row_derives_columns():
    row = check()
    assert (row.film_id, row.rating, row.private, row.watched_on) == (
        "Q949228",
        4.5,
        False,
        date(2026, 9, 30),
    )
    assert row.fresh  # public, day precision, within 14 days
    assert row.film == KANTARA


def test_stub_freshness():
    old = check(data={**STUB, "date": "2026-09-01"})
    assert not old.fresh and old.watched_on == date(2026, 9, 1)
    assert not check(data={**STUB, "priv": True}).fresh
    assert check(data={**STUB, "priv": True}).private
    assert not check(data={**STUB, "prec": "month"}).fresh
    assert check(data={**STUB, "prec": "month"}).watched_on is None
    assert check(data={**STUB, "date": "2026-10-02"}).fresh  # tomorrow on a clock ahead of UTC
    assert not check(data={**STUB, "date": "2026-10-09"}).fresh
    no_date = {k: v for k, v in STUB.items() if k != "date"}
    assert not check(data=no_date).fresh


def test_updated_at_is_clamped_to_five_minutes_ahead():
    assert check(at=NOW + timedelta(days=3)).updated_at == NOW + timedelta(minutes=5)
    assert check(at=NOW - timedelta(days=3)).updated_at == NOW - timedelta(days=3)


def test_tombstones_keep_nothing_but_the_time():
    row = check(deleted=True, film=KANTARA, data={"memo": "x"})
    assert (row.deleted, row.film, row.data, row.film_id) == (True, None, {}, None)
    assert check("wish", "Q949228", deleted=True).film_id == "Q949228"


@pytest.mark.parametrize(
    "data",
    [
        {**STUB, "film": "x"},
        {**STUB, "film": "Q1.5"},
        {**STUB, "rating": 0.0},
        {**STUB, "rating": 5.1},
        {**STUB, "rating": "4"},
        {**STUB, "rating": True},
        {**STUB, "rating": float("nan")},
        {**STUB, "priv": "yes"},
        {**STUB, "prec": "hour"},
        {**STUB, "date": "30/09/2026"},
        {**STUB, "date": "2026-02-30"},
        {**STUB, "id": "other"},
        {**STUB, "memo": "a\x00b"},
        {**STUB, "deep": {"a": {"b": {"c": {"d": {"e": {"f": {"g": {"h": {"i": 1}}}}}}}}}},
    ],
)
def test_bad_stubs(data):
    with pytest.raises(RecordError) as caught:
        check(data=data)
    assert caught.value.code == "invalid_record"


def test_stub_needs_a_film_snapshot_and_a_sane_id():
    with pytest.raises(RecordError):
        check(film=None)
    for rid in ("", "x" * 65, "a\x00b", "a\nb"):
        with pytest.raises(RecordError):
            check(rid=rid, data={**STUB, "id": rid})


def test_stub_too_large():
    with pytest.raises(RecordError) as caught:
        check(data={**STUB, "memo": "m" * 17000})
    assert caught.value.code == "too_large"


def test_wish_meta_taste():
    wish = {"film": "Q949228", "added": "2026-09-01T10:00:00.000"}
    assert check("wish", "Q949228", data=wish).film_id == "Q949228"
    assert (
        check(
            "wish", "my:dev1.2", data={"film": "my:dev1.2"}, film={"id": "my:dev1.2", "t": "Mine"}
        ).film_id
        == "my:dev1.2"
    )
    with pytest.raises(RecordError):
        check("wish", "Q949228", data={"film": "Q1"})
    with pytest.raises(RecordError):
        check("wish", "not-a-film", data={})
    meta = {"tags": ["a"], "venues": [{"name": "Home", "type": "home"}], "hidden": ["Q1"]}
    assert check("meta", "meta", data=meta, film=KANTARA).film is None
    with pytest.raises(RecordError):
        check("meta", "other", data=meta)
    with pytest.raises(RecordError):
        check("meta", "meta", data={"tags": "a"})
    with pytest.raises(RecordError):
        check("meta", "meta", data={"venues": ["Home"]})
    assert check("taste", "taste", data={"v": 1, "traits": []}).data == {"v": 1, "traits": []}
    with pytest.raises(RecordError):
        check("taste", "taste", data={"traits": []})
    with pytest.raises(RecordError) as caught:
        check("taste", "taste", data={"v": 1, "pad": "x" * 25000})
    assert caught.value.code == "too_large"


def test_unknown_kind():
    with pytest.raises(RecordError):
        validate_record("memo", "x", NOW, False, None, {}, NOW)


# --- the limiter ------------------------------------------------------------


def test_limiter_sliding_window_with_a_fake_clock():
    clock = FakeClock()
    limiter = Limiter(clock)
    limit, window = RULES["join"]
    for _ in range(limit):
        limiter.check("join", "u1")
    with pytest.raises(RateLimited) as caught:
        limiter.check("join", "u1")
    assert caught.value.headers["Retry-After"] == str(int(window))
    limiter.check("join", "u2")  # another key has its own window
    clock.advance(window - 1)
    with pytest.raises(RateLimited) as caught:
        limiter.check("join", "u1")
    assert caught.value.headers["Retry-After"] == "1"
    clock.advance(1)
    limiter.check("join", "u1")  # the first hit left the window


def test_limiter_window_slides_instead_of_resetting():
    clock = FakeClock()
    limiter = Limiter(clock)  # message: 30 per 60 s
    for _ in range(15):
        limiter.check("message", "u")
    clock.advance(30)
    for _ in range(15):
        limiter.check("message", "u")
    with pytest.raises(RateLimited):
        limiter.check("message", "u")
    clock.advance(31)  # the first 15 are out, the second 15 are not
    for _ in range(15):
        limiter.check("message", "u")
    with pytest.raises(RateLimited):
        limiter.check("message", "u")


def test_limiter_deck_is_one_write_per_ten_seconds_per_group_and_user():
    clock = FakeClock()
    limiter = Limiter(clock)
    limiter.check("deck", "g1:u1")
    limiter.check("deck", "g1:u2")  # another member's budget is untouched
    with pytest.raises(RateLimited):
        limiter.check("deck", "g1:u1")
    clock.advance(10)
    limiter.check("deck", "g1:u1")


def test_limiter_has_a_refresh_rule():
    clock = FakeClock()
    limiter = Limiter(clock)
    limit, window = RULES["refresh_ip"]
    for _ in range(limit):
        limiter.check("refresh_ip", "ip1")
    with pytest.raises(RateLimited):
        limiter.check("refresh_ip", "ip1")
    limiter.check("refresh_ip", "ip2")


def test_limiter_forgets_idle_keys():
    clock = FakeClock()
    limiter = Limiter(clock)
    for i in range(999):
        limiter.check("lookup", f"u{i}")
    clock.advance(4000)
    limiter.check("lookup", "late")  # the 1000th call sweeps
    assert list(limiter._hits) == [("lookup", "late")]


# --- client_ip: the rate limiter's view of the caller ------------------------


def _request(host: str | None, headers: dict[str, str] | None = None) -> Request:
    return Request(
        {
            "type": "http",
            "client": (host, 1234) if host else None,
            "headers": [(k.lower().encode(), v.encode()) for k, v in (headers or {}).items()],
        }
    )


def test_client_ip_uses_the_socket_address():
    assert client_ip(_request("203.0.0.9")) == "203.0.0.9"
    assert client_ip(_request(None)) == "unknown"


def test_client_ip_fails_closed_on_an_untrusted_forwarded_header(caplog):
    # A forwarded header on a socket address that is not our proxy means the
    # --proxy-headers pass did not run: refuse rather than share one bucket.
    with caplog.at_level(logging.ERROR, logger="talkies"), pytest.raises(RateLimited):
        client_ip(_request("203.0.0.9", {"x-forwarded-for": "1.2.3.4"}))
    assert "--proxy-headers" in caplog.text
    # A trusted proxy address, or no forwarded header at all, is fine.
    assert client_ip(_request("127.0.0.1", {"x-forwarded-for": "1.2.3.4"})) == "127.0.0.1"
    assert client_ip(_request("203.0.0.9", {"user-agent": "x"})) == "203.0.0.9"
