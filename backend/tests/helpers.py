"""Helpers shared by the pure tests and the database tests."""

import time
from typing import Any
from uuid import UUID, uuid4

import httpx
import jwt
from fastapi import FastAPI

from app.auth.deps import ACCOUNT_EXISTS
from app.db import Db
from app.main import create_app
from app.ratelimit import Limiter
from app.settings import Settings

SUPABASE_URL = "https://project.supabase.test"
JWT_SECRET = "test-secret-test-secret-test-secret-123456"


class FakeClock:
    """A clock that only moves when the test says so."""

    def __init__(self, now: float = 1000.0):
        self.now = now

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


def make_settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {
        "supabase_url": SUPABASE_URL,
        "supabase_anon_key": "anon-key",
        "supabase_service_role_key": "service-key",
        "supabase_jwt_secret": JWT_SECRET,
        "database_url": "",
        "public_base_url": "https://api.talkies.test",
        "auth_providers": "email,google,apple",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def make_app(settings: Settings | None = None, handler=None, **kwargs: Any) -> FastAPI:
    """An app whose HTTP client answers with `handler` (a MockTransport handler)."""
    settings = settings or make_settings()
    http = httpx.AsyncClient(transport=httpx.MockTransport(handler or _no_network))
    kwargs.setdefault("limiter", Limiter())
    return create_app(settings, http=http, **kwargs)


def _no_network(request: httpx.Request) -> httpx.Response:
    raise AssertionError(f"unexpected call to {request.url}")


def client_for(app: FastAPI, **kwargs: Any) -> httpx.AsyncClient:
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://testserver", **kwargs)


class AccountStub(Db):
    """A database that answers only the signed-in account check.

    Every request with a token asks `current_user` whether the account still
    exists. Tests that are about something else (the body limit, the error
    envelope) pass this so that check passes and their own route runs.
    """

    async def fetchrow(self, sql: str, *args: Any):
        if " ".join(sql.split()) == ACCOUNT_EXISTS:
            return {"?column?": 1}
        raise AssertionError(f"unexpected query: {sql.strip()[:120]}")


def account_db() -> AccountStub:
    return AccountStub("")


def make_token(
    user_id: UUID | None = None,
    key: Any = JWT_SECRET,
    alg: str = "HS256",
    kid: str | None = None,
    **claims: Any,
) -> str:
    """A Supabase-shaped access token. A claim set to None is left out."""
    now = int(time.time())
    body: dict[str, Any] = {
        "iss": f"{SUPABASE_URL}/auth/v1",
        "aud": "authenticated",
        "sub": str(user_id or uuid4()),
        "role": "authenticated",
        "is_anonymous": False,
        "iat": now,
        "exp": now + 3600,
    }
    body.update(claims)
    body = {k: v for k, v in body.items() if v is not None}
    headers = {"kid": kid} if kid else None
    return jwt.encode(body, key, algorithm=alg, headers=headers)


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}
