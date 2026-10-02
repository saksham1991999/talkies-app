"""Sign in with Apple revocation (rule 4.8): exchange, revoke, and the gaps."""

from uuid import uuid4

import httpx

from app.auth.apple import Apple
from tests.helpers import auth, client_for, make_app, make_settings, make_token
from tests.scripted import ScriptedConn, ScriptedDb

USER = uuid4()
HEADERS = auth(make_token(USER))
APPLE_TOKEN = "https://appleid.apple.com/auth/token"
APPLE_REVOKE = "https://appleid.apple.com/auth/revoke"
SESSION = {
    "access_token": "access",
    "refresh_token": "refresh",
    "expires_at": 1800000000,
    "token_type": "bearer",
    "user": {"id": str(USER), "email": "a@privaterelay.appleid.com"},
}


class Replies:
    """Sends every request to a log and answers by URL."""

    def __init__(self, revoke_status: int = 200):
        self.requests: list[httpx.Request] = []
        self.revoke_status = revoke_status

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if request.url == APPLE_TOKEN:
            return httpx.Response(200, json={"refresh_token": "apple-refresh"})
        if request.url == APPLE_REVOKE:
            return httpx.Response(self.revoke_status, json={})
        if request.url.path.startswith("/auth/v1/"):
            return httpx.Response(200, json=SESSION)
        raise AssertionError(f"unexpected call to {request.url}")

    def form(self, url: str) -> dict:
        request = next(r for r in self.requests if r.url == url)
        return dict(pair.split("=", 1) for pair in request.content.decode().split("&"))

    def called(self, url: str) -> bool:
        return any(r.url == url for r in self.requests)


def apple_settings(**over):
    return make_settings(**{
        "apple_client_id": "in.talkies.talkies", "apple_client_secret": "secret-jwt", **over
    })


def app_for(handler, steps=(), settings=None):
    conn = ScriptedConn(*steps)
    app = make_app(settings=handler and settings or None, handler=handler, db=ScriptedDb(conn))
    return app, conn


def body(provider="apple", **over):
    base = {
        "provider": provider,
        "id_token": "apple-identity-token",
        "nonce": "raw-nonce",
        "authorization_code": "apple-code",
    }
    return {**base, **over}


async def test_sign_in_exchanges_the_code_and_stores_the_refresh_token():
    up = Replies()
    app, conn = app_for(up, [("insert into profiles", "INSERT 0 1")], apple_settings())
    async with client_for(app) as client:
        reply = await client.post("/v1/auth/id-token", json=body())
    assert reply.status_code == 200
    form = up.form(APPLE_TOKEN)
    assert form["grant_type"] == "authorization_code"
    assert form["code"] == "apple-code"
    assert form["client_id"] == "in.talkies.talkies"
    assert conn.args_of("insert into profiles") == (USER, "apple-refresh")
    conn.finished()


async def test_sign_in_without_a_code_stores_nothing_and_skips_apple():
    up = Replies()
    app, conn = app_for(up, [], apple_settings())
    async with client_for(app) as client:
        reply = await client.post("/v1/auth/id-token", json=body(authorization_code=None))
    assert reply.status_code == 200
    assert not up.called(APPLE_TOKEN)
    conn.finished()


async def test_sign_in_without_apple_configured_skips_the_exchange():
    up = Replies()
    app, conn = app_for(up, [], apple_settings(apple_client_id="", apple_client_secret=""))
    async with client_for(app) as client:
        reply = await client.post("/v1/auth/id-token", json=body())
    assert reply.status_code == 200
    assert not up.called(APPLE_TOKEN)
    conn.finished()


async def test_a_failed_exchange_still_signs_the_user_in():
    up = Replies(revoke_status=200)

    def handler(request):
        if request.url == APPLE_TOKEN:
            return httpx.Response(400, json={"error": "invalid_grant"})
        return up(request)

    app, conn = app_for(handler, [], apple_settings())
    async with client_for(app) as client:
        reply = await client.post("/v1/auth/id-token", json=body())
    assert reply.status_code == 200
    assert reply.json()["access_token"] == "access"
    conn.finished()


async def test_delete_revokes_the_stored_apple_grant():
    up = Replies()
    app, conn = app_for(
        up,
        [
            ("pg_advisory_xact_lock", None),
            ("from profiles where id = $1", "apple-refresh"),
            ("pg_advisory_xact_lock", None),  # the delete re-locks after GoTrue
            ("select delete_account($1)", None),
        ],
        apple_settings(),
    )
    async with client_for(app) as client:
        reply = await client.delete("/v1/me", headers=HEADERS)
    assert reply.status_code == 204
    form = up.form(APPLE_REVOKE)
    assert form["token"] == "apple-refresh"
    assert form["token_type_hint"] == "refresh_token"
    assert conn.args_of("select delete_account") == (USER,)
    conn.finished()


async def test_delete_without_a_stored_token_skips_the_revoke():
    up = Replies()
    app, conn = app_for(
        up,
        [
            ("pg_advisory_xact_lock", None),
            ("from profiles where id = $1", None),
            ("pg_advisory_xact_lock", None),  # the delete re-locks after GoTrue
            ("select delete_account($1)", None),
        ],
        apple_settings(),
    )
    async with client_for(app) as client:
        reply = await client.delete("/v1/me", headers=HEADERS)
    assert reply.status_code == 204
    assert not up.called(APPLE_REVOKE)
    conn.finished()


async def test_delete_without_apple_configured_skips_the_revoke():
    up = Replies()
    app, conn = app_for(
        up,
        [
            ("pg_advisory_xact_lock", None),
            ("from profiles where id = $1", "apple-refresh"),
            ("pg_advisory_xact_lock", None),  # the delete re-locks after GoTrue
            ("select delete_account($1)", None),
        ],
        apple_settings(apple_client_id="", apple_client_secret=""),
    )
    async with client_for(app) as client:
        reply = await client.delete("/v1/me", headers=HEADERS)
    assert reply.status_code == 204
    assert not up.called(APPLE_REVOKE)
    conn.finished()


async def test_delete_proceeds_when_apple_refuses_to_revoke():
    up = Replies(revoke_status=500)
    app, conn = app_for(
        up,
        [
            ("pg_advisory_xact_lock", None),
            ("from profiles where id = $1", "apple-refresh"),
            ("pg_advisory_xact_lock", None),  # the delete re-locks after GoTrue
            ("select delete_account($1)", None),
        ],
        apple_settings(),
    )
    async with client_for(app) as client:
        reply = await client.delete("/v1/me", headers=HEADERS)
    assert reply.status_code == 204
    assert up.called(APPLE_REVOKE)
    conn.finished()


async def test_exchange_returns_none_when_apple_is_down():
    def handler(request):
        raise httpx.ConnectError("down")

    apple = Apple(apple_settings(), httpx.AsyncClient(transport=httpx.MockTransport(handler)))
    assert await apple.exchange("code") is None
