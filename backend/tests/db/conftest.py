"""Fixtures for the database tests.

They need a real Postgres. Set TEST_DATABASE_URL to an EMPTY database whose name
contains "test". The tests drop and rebuild its `public` and `auth` schemas.
Without the variable every test in this folder is skipped.
"""

import asyncio
import json
import os
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

import asyncpg
import httpx
import pytest
import pytest_asyncio

from app.main import create_app
from app.ratelimit import Limiter
from tests.helpers import SUPABASE_URL, FakeClock, auth, make_settings, make_token

URL = os.environ.get("TEST_DATABASE_URL", "")
HERE = Path(__file__).resolve().parent
MIGRATIONS = sorted((HERE.parents[2] / "supabase" / "migrations").glob("*.sql"))

requires_db = pytest.mark.skipif(not URL, reason="TEST_DATABASE_URL is not set")

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


def film(film_id: str = "Q949228", title: str | None = None) -> dict:
    return {
        **KANTARA,
        "id": film_id,
        "t": title or (KANTARA["t"] if film_id == "Q949228" else film_id),
    }


def iso(moment: datetime) -> str:
    return (
        moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond // 1000:03d}Z"
    )


def stub(
    stub_id: str,
    film_id: str = "Q949228",
    *,
    date: str | None = None,
    rating: float | None = None,
    private: bool = False,
    at: datetime | None = None,
    **extra: Any,
) -> dict:
    """A sync record for a stub, shaped like the phone's `Stub.toJson()`."""
    data: dict[str, Any] = {
        "id": stub_id,
        "no": 1,
        "film": film_id,
        "created": "2026-01-01T10:00:00.000",
        "prec": "day",
    }
    if date:
        data["date"] = date
    if rating is not None:
        data["rating"] = rating
    if private:
        data["priv"] = True
    data.update(extra)
    return {
        "kind": "stub",
        "id": stub_id,
        "updated_at": iso(at or datetime.now(UTC)),
        "deleted": False,
        "film": film(film_id),
        "data": data,
    }


def wish(film_id: str = "Q949228", *, at: datetime | None = None, **extra: Any) -> dict:
    data = {"film": film_id, "added": "2026-01-01T10:00:00.000", **extra}
    return {
        "kind": "wish",
        "id": film_id,
        "updated_at": iso(at or datetime.now(UTC)),
        "deleted": False,
        "film": film(film_id),
        "data": data,
    }


def today() -> str:
    return datetime.now(UTC).date().isoformat()


async def _prepare(url: str) -> None:
    conn = await asyncpg.connect(url)
    try:
        name = await conn.fetchval("select current_database()")
        assert "test" in name, f"refusing to rebuild {name!r}: the name must contain 'test'"
        await conn.execute("drop schema if exists public cascade")
        await conn.execute("drop schema if exists auth cascade")
        await conn.execute("create schema public")
        await conn.execute((HERE / "00_supabase_stub.sql").read_text())
        for path in MIGRATIONS:
            await conn.execute(path.read_text())
        # With usage on the schema, a denied query fails on the table itself.
        await conn.execute("grant usage on schema public to anon, authenticated")
    finally:
        await conn.close()


@pytest.fixture(scope="session")
def database_url() -> str:
    if not URL:
        pytest.skip("TEST_DATABASE_URL is not set")
    asyncio.run(_prepare(URL))
    return URL


async def _set_codec(conn: asyncpg.Connection) -> None:
    await conn.set_type_codec(
        "jsonb",
        encoder=lambda v: json.dumps(v, default=str),
        decoder=json.loads,
        schema="pg_catalog",
    )


class Client:
    """One signed-in user talking to the app."""

    def __init__(self, http: httpx.AsyncClient, user_id: UUID, name: str):
        self.http = http
        self.id = user_id
        self.name = name
        self.token = make_token(user_id)

    @property
    def headers(self) -> dict[str, str]:
        return auth(self.token)

    async def get(self, path: str, **params: Any) -> httpx.Response:
        return await self.http.get(path, params=params, headers=self.headers)

    async def post(self, path: str, json: Any = None) -> httpx.Response:
        return await self.http.post(path, json=json, headers=self.headers)

    async def put(self, path: str, json: Any = None) -> httpx.Response:
        return await self.http.put(path, json=json, headers=self.headers)

    async def patch(self, path: str, json: Any = None) -> httpx.Response:
        return await self.http.patch(path, json=json, headers=self.headers)

    async def delete(self, path: str, json: Any = None) -> httpx.Response:
        return await self.http.delete(path, headers=self.headers)

    async def ok(self, method: str, path: str, json: Any = None, status: int = 200, **params: Any):
        """Call, assert the status, and return the JSON body (None for 204)."""
        if method == "get":
            reply = await self.get(path, **params)
        else:
            reply = await getattr(self, method)(path, json)
        assert reply.status_code == status, f"{method} {path}: {reply.status_code} {reply.text}"
        return reply.json() if reply.content else None

    async def push(self, *records: dict) -> dict:
        return await self.ok("post", "/v1/sync/push", {"records": list(records)})

    async def pull(self, after: int = 0, limit: int = 200) -> dict:
        return await self.ok("get", "/v1/sync/pull", after=after, limit=limit)


class World:
    def __init__(self, url: str, http: httpx.AsyncClient, pg: asyncpg.Connection, clock: FakeClock):
        self.url = url
        self.http = http
        self.pg = pg
        self.clock = clock
        self.auth_deleted: list[str] = []
        self.auth_status = 200  # what the mocked Supabase Auth answers to a user delete

    async def user(
        self,
        name: str,
        *,
        visibility: str = "private",
        share_ratings: bool = False,
    ) -> Client:
        user_id = uuid4()
        await self.pg.execute(
            "insert into auth.users (id, email) values ($1, $2)", user_id, f"{name}@x.test"
        )
        client = Client(self.http, user_id, name)
        await client.ok("get", "/v1/me")
        patch = {"handle": name, "display_name": name.capitalize(), "visibility": visibility}
        await client.ok("patch", "/v1/me", {**patch, "share_ratings": share_ratings})
        return client

    async def friends(self, a: Client, b: Client) -> None:
        await a.ok("post", "/v1/friends/requests", {"user_id": str(b.id)})
        await b.ok("post", f"/v1/friends/requests/{a.id}/accept", status=204)

    async def group(self, owner: Client, name: str = "Crew", *members: Client) -> dict:
        group = await owner.ok("post", "/v1/groups", {"name": name}, status=201)
        for member in members:
            await member.ok("post", "/v1/groups/join", {"code": group["invite_code"]})
        return group

    async def rows(self, sql: str, *args: Any) -> list[asyncpg.Record]:
        return await self.pg.fetch(sql, *args)

    async def value(self, sql: str, *args: Any) -> Any:
        return await self.pg.fetchval(sql, *args)


@pytest_asyncio.fixture
async def world(database_url: str) -> AsyncIterator[World]:
    pg = await asyncpg.connect(database_url)
    await _set_codec(pg)
    await pg.execute("truncate auth.users cascade")  # every table points back at it
    # reports_archive holds no user id, so it survives the truncate: clear it here.
    await pg.execute("delete from reports_archive")
    clock = FakeClock()
    holder: dict[str, World] = {}

    async def supabase(request: httpx.Request) -> httpx.Response:
        """Supabase Auth, mocked. A user delete also removes the auth row, like the real one."""
        prefix = f"{SUPABASE_URL}/auth/v1/admin/users/"
        if request.method == "DELETE" and str(request.url).startswith(prefix):
            user_id = str(request.url).removeprefix(prefix)
            holder["world"].auth_deleted.append(user_id)
            status = holder["world"].auth_status
            if status == 200:
                await pg.execute("delete from auth.users where id = $1", UUID(user_id))
            return httpx.Response(status, json={})
        raise AssertionError(f"unexpected call to {request.url}")

    settings = make_settings(database_url=database_url)
    http = httpx.AsyncClient(transport=httpx.MockTransport(supabase))
    app = create_app(settings, http=http, limiter=Limiter(clock))
    transport = httpx.ASGITransport(app=app)
    client = httpx.AsyncClient(transport=transport, base_url="http://testserver")
    holder["world"] = World(database_url, client, pg, clock)
    try:
        yield holder["world"]
    finally:
        await client.aclose()
        await app.state.db.close()
        await http.aclose()
        await pg.close()
