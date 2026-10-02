"""The app boots with no database, and the error envelope holds everywhere."""

import re
from collections.abc import AsyncIterator

import asyncpg
import httpx
import pytest

from app.db import Db
from app.errors import DbUnavailable
from tests.helpers import (
    FakeClock,
    account_db,
    auth,
    client_for,
    make_app,
    make_settings,
    make_token,
)

CODE = "K7M2QX9P"


async def test_boots_with_no_database_at_all():
    async with client_for(make_app()) as client:
        reply = await client.get("/healthz")
        assert reply.status_code == 503
        assert reply.json() == {"ok": False, "api": 1, "auth": []}
        page = await client.get(f"/j/{CODE}")
        assert page.status_code == 200


async def test_healthz_when_the_database_answers():
    class Up(Db):
        async def _ping(self) -> bool:
            return True

    app = make_app(db=Up(""))
    async with client_for(app) as client:
        reply = await client.get("/healthz")
    assert reply.status_code == 200
    assert reply.json() == {"ok": True, "api": 1, "auth": ["email", "google", "apple"]}


async def test_healthz_lists_only_the_configured_providers():
    class Up(Db):
        async def _ping(self) -> bool:
            return True

    app = make_app(make_settings(auth_providers=" Apple , bogus ,email"), db=Up(""))
    async with client_for(app) as client:
        assert (await client.get("/healthz")).json()["auth"] == ["email", "apple"]
    app = make_app(make_settings(auth_providers=""), db=Up(""))
    async with client_for(app) as client:
        assert (await client.get("/healthz")).json()["auth"] == ["email"]


async def test_the_database_check_is_cached_for_five_seconds():
    class Counting(Db):
        pings = 0
        answer = True

        async def _ping(self) -> bool:
            self.pings += 1
            return self.answer

    clock = FakeClock()
    db = Counting("", clock=clock)
    assert await db.healthy() and await db.healthy()
    assert db.pings == 1
    db.answer = False
    clock.advance(4.9)
    assert await db.healthy()  # still the cached answer
    clock.advance(0.2)
    assert not await db.healthy()
    assert db.pings == 2


async def test_an_unset_database_is_503_not_a_crash():
    app = make_app()
    async with client_for(app) as client:
        reply = await client.get("/v1/me", headers=auth(make_token()))
    assert reply.status_code == 503
    assert reply.json()["error"]["code"] == "db_unavailable"


async def test_pool_is_not_created_until_needed(monkeypatch):
    calls = []

    async def fake_create_pool(*args, **kwargs):
        calls.append(kwargs)
        raise OSError("refused")

    monkeypatch.setattr(asyncpg, "create_pool", fake_create_pool)
    clock = FakeClock()
    db = Db("postgres://u:p@localhost/db", clock=clock)
    assert calls == []
    with pytest.raises(DbUnavailable):
        await db.pool()
    assert len(calls) == 1
    assert calls[0]["statement_cache_size"] == 0
    assert callable(calls[0]["init"])
    # After a failure the next attempt waits two seconds, so a down database is not hammered.
    clock.advance(1)
    with pytest.raises(DbUnavailable):
        await db.pool()
    assert len(calls) == 1
    clock.advance(1.5)
    with pytest.raises(DbUnavailable):
        await db.pool()
    assert len(calls) == 2


async def test_a_pool_that_lost_its_database_is_dropped_and_cooled_down(monkeypatch):
    """A pool that was fine at boot still has to back off once the database goes away."""
    made = []

    class DeadPool:
        closed = False

        async def acquire(self, timeout=None):  # noqa: ASYNC109 - asyncpg's own signature
            raise asyncpg.ConnectionDoesNotExistError("server closed the connection")

        async def close(self):
            self.closed = True

    async def fake_create_pool(*args, **kwargs):
        pool = DeadPool()
        made.append(pool)
        return pool

    monkeypatch.setattr(asyncpg, "create_pool", fake_create_pool)
    clock = FakeClock()
    db = Db("postgres://u:p@localhost/db", clock=clock)
    with pytest.raises(DbUnavailable):
        async with db.conn():
            pass
    assert made[0].closed  # the broken pool does not stay in service
    assert db._pool is None
    # The next request inside the cooldown does not even try to connect again.
    with pytest.raises(DbUnavailable):
        async with db.conn():
            pass
    assert len(made) == 1
    clock.advance(2.5)
    with pytest.raises(DbUnavailable):
        async with db.conn():
            pass
    assert len(made) == 2  # the cooldown expired, so it tried once more


# --- the invite page --------------------------------------------------------


async def test_invite_page_content_and_headers():
    async with client_for(make_app()) as client:
        reply = await client.get(f"/j/{CODE}")
    assert reply.headers["x-robots-tag"] == "noindex"
    assert reply.headers["referrer-policy"] == "no-referrer"
    assert reply.headers["content-type"].startswith("text/html")
    page = reply.text
    assert CODE[:4] in page and CODE[4:] in page
    assert f'href="talkies://join?code={CODE}"' in page
    assert "Open in Talkies" in page
    assert "https://apps.apple.com/app/id6817738462" in page
    assert "https://play.google.com/store/apps/details?id=in.talkies.talkies" in page
    assert "api.fontshare.com/v2/css?f[]=tanker@400" in page
    assert 'og:url" content="https://api.talkies.test/j/K7M2QX9P"' in page


@pytest.mark.parametrize(
    "code",
    [
        "k7m2qx9p",
        "K7M2QX9",
        "K7M2QX9PP",
        "K7M2QX90",
        "K7M2QX9O",
        "K7M2QX9I",
        "K7M2QX91",
        "K7M2QX9L",
        "K7M2-X9P",
    ],
)
async def test_invite_page_refuses_a_malformed_code(code):
    async with client_for(make_app()) as client:
        reply = await client.get(f"/j/{code}")
    assert reply.status_code == 404
    assert reply.json()["error"]["code"] == "not_found"


async def test_invite_page_follows_the_design_rules():
    async with client_for(make_app()) as client:
        page = (await client.get(f"/j/{CODE}")).text
    assert chr(0x2014) not in page and chr(0x2013) not in page  # no em or en dash
    assert "<script" not in page.lower()
    lowered = page.lower()
    for banned in (
        "gradient",
        "box-shadow",
        "text-shadow",
        "drop-shadow",
        "blur(",
        "translate(",
        "scale(",
    ):
        assert banned not in lowered, banned
    assert "--wall:#e3e6d8" in page and "--paper:#f2cbc1" in page and "--ink:#2a1316" in page
    assert "--sindoor:#b0342b" in page and "prefers-color-scheme:dark" in page
    radii = re.findall(r"border-radius:([^;}]+)", page)
    assert set(radii) == {"6px", "50%", "4px"}
    assert "9999" not in page  # no pill


async def test_invite_page_without_a_public_base_url_has_no_og_url():
    async with client_for(make_app(make_settings(public_base_url=""))) as client:
        assert "og:url" not in (await client.get(f"/j/{CODE}")).text


# --- the envelope -----------------------------------------------------------


async def test_missing_or_bad_token_is_401_with_the_envelope():
    async with client_for(make_app()) as client:
        for headers in (
            {},
            {"Authorization": "Basic abc"},
            {"Authorization": "Bearer"},
            auth("junk"),
        ):
            reply = await client.get("/v1/me", headers=headers)
            assert reply.status_code == 401
            assert reply.json() == {
                "error": {"code": "unauthorized", "message": "Sign in required", "detail": None}
            }
            assert reply.headers["www-authenticate"] == "Bearer"


async def test_unknown_route_and_wrong_method_use_the_envelope():
    async with client_for(make_app()) as client:
        missing = await client.get("/v1/nothing")
        assert missing.status_code == 404
        assert missing.json()["error"]["code"] == "not_found"
        wrong = await client.delete("/healthz")
        assert wrong.status_code == 405
        assert wrong.json()["error"]["code"] == "method_not_allowed"


async def test_bodies_over_2_mb_are_413_with_or_without_a_length():
    async with client_for(make_app()) as client:
        big = b'{"records":[],"pad":"' + b"x" * (2 * 1024 * 1024) + b'"}'
        reply = await client.post("/v1/sync/push", content=big, headers=auth(make_token()))
        assert reply.status_code == 413
        assert reply.json()["error"]["code"] == "too_large"

        async def stream() -> AsyncIterator[bytes]:
            for _ in range(5):
                yield b"x" * (500 * 1024)

        reply = await client.post("/v1/sync/push", content=stream(), headers=auth(make_token()))
        assert reply.status_code == 413


async def test_a_body_just_under_the_limit_reaches_the_route():
    # The account check needs a database; this test is about the body, so stub
    # that one query and let the route reach its own validation.
    async with client_for(make_app(db=account_db())) as client:
        body = b'{"records":[],"pad":"' + b"x" * (2 * 1024 * 1024 - 100) + b'"}'
        reply = await client.post("/v1/sync/push", content=body, headers=auth(make_token()))
    assert reply.status_code == 422  # unknown key `pad`: it was read and checked, not cut off


async def test_database_errors_map_to_the_envelope():
    app = make_app()

    @app.get("/boom/{kind}")
    async def boom(kind: str):
        raise {
            "down": asyncpg.PostgresConnectionError("x"),
            "refused": ConnectionRefusedError(),
            "fk": asyncpg.ForeignKeyViolationError("x"),
            "unique": asyncpg.UniqueViolationError("x"),
            "check": asyncpg.CheckViolationError("x"),
            "data": asyncpg.DataError("x"),
            "bug": RuntimeError("secret detail"),
        }[kind]

    transport = httpx.ASGITransport(app=app, raise_app_exceptions=False)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
        expected = {
            "down": (503, "db_unavailable"),
            "refused": (503, "db_unavailable"),
            "fk": (404, "not_found"),
            "unique": (409, "conflict"),
            "check": (422, "invalid_request"),
            "data": (422, "invalid_request"),
            "bug": (500, "internal"),
        }
        for kind, (status, code) in expected.items():
            reply = await client.get(f"/boom/{kind}")
            assert (reply.status_code, reply.json()["error"]["code"]) == (status, code), kind
            assert "secret detail" not in reply.text


async def test_openapi_builds_and_there_is_no_docs_page():
    app = make_app()
    spec = app.openapi()
    assert "/healthz" in spec["paths"]
    async with client_for(app) as client:
        assert (await client.get("/docs")).status_code == 404
