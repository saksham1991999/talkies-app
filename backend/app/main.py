"""The FastAPI app. Run: uvicorn app.main:app --proxy-headers --forwarded-allow-ips='*'"""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from app.auth.apple import Apple
from app.auth.gotrue import GoTrue
from app.auth.jwt import Verifier
from app.auth.router import router as auth_router
from app.db import Db
from app.errors import envelope, install_handlers
from app.ratelimit import Limiter
from app.routers import (
    chat,
    decks,
    feed,
    friends,
    groups,
    health,
    invite,
    me,
    nights,
    safety,
    sync,
    users,
    wrapup,
)
from app.settings import Settings, get_settings

log = logging.getLogger("talkies")

MAX_BODY = 2 * 1024 * 1024


class BodyLimit:
    """Answer 413 to a request body over `limit` bytes, before any route runs.

    The body is read up to the limit and handed on, so a body without a
    Content-Length header is limited too.
    """

    def __init__(self, app: ASGIApp, limit: int = MAX_BODY):
        self.app = app
        self.limit = limit

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        declared = dict(scope["headers"]).get(b"content-length", b"")
        if declared.isdigit() and int(declared) > self.limit:
            await self._refuse(scope, receive, send)
            return
        body = await self._read(receive)
        if body is None:
            await self._refuse(scope, receive, send)
            return
        sent = False

        async def replay():
            nonlocal sent
            if sent:
                return await receive()
            sent = True
            return {"type": "http.request", "body": body, "more_body": False}

        await self.app(scope, replay, send)

    async def _read(self, receive: Receive) -> bytes | None:
        chunks: list[bytes] = []
        size = 0
        while True:
            message = await receive()
            if message["type"] != "http.request":
                return b"".join(chunks)  # the client left: the app sees a short body
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > self.limit:
                return None
            chunks.append(chunk)
            if not message.get("more_body", False):
                return b"".join(chunks)

    async def _refuse(self, scope: Scope, receive: Receive, send: Send) -> None:
        response = JSONResponse(
            envelope("too_large", "Request body is too large"),
            status_code=413,
            headers={"Connection": "close"},
        )
        await response(scope, receive, send)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings: Settings = app.state.settings
    missing = [
        name
        for name, value in (
            ("SUPABASE_URL", settings.supabase_url),
            ("SUPABASE_ANON_KEY", settings.supabase_anon_key),
            ("SUPABASE_SERVICE_ROLE_KEY", settings.supabase_service_role_key),
            ("DATABASE_URL", settings.database_url),
        )
        if not value
    ]
    if missing:
        log.warning("not set: %s. Related routes answer 502 or 503.", ", ".join(missing))
    yield
    await app.state.db.close()
    await app.state.http.aclose()


def create_app(
    settings: Settings | None = None,
    *,
    http: httpx.AsyncClient | None = None,
    db: Db | None = None,
    limiter: Limiter | None = None,
) -> FastAPI:
    """Build the app. The keyword arguments let tests replace the parts."""
    settings = settings or get_settings()
    http = http or httpx.AsyncClient(timeout=8.0)
    app = FastAPI(
        title="Talkies API", version="1", lifespan=lifespan, docs_url=None, redoc_url=None
    )
    app.state.settings = settings
    app.state.http = http
    app.state.db = db or Db(settings.dsn, settings.db_pool_max)
    app.state.limiter = limiter or Limiter()
    app.state.verifier = Verifier(settings, http)
    app.state.gotrue = GoTrue(settings, http)
    app.state.apple = Apple(settings, http)
    app.add_middleware(BodyLimit)
    install_handlers(app)
    for router in (
        health.router,
        invite.router,
        auth_router,
        me.router,
        sync.router,
        friends.router,
        users.router,
        feed.router,
        safety.router,
        groups.router,
        decks.router,
        nights.router,
        chat.router,
        wrapup.router,
    ):
        app.include_router(router)
    return app


app = create_app()
