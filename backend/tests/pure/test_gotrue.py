"""The Supabase Auth proxy, against a mocked transport. Plus the /v1/auth routes."""

import json
from uuid import uuid4

import httpx
import pytest

from app.auth.gotrue import GoTrue
from app.errors import ApiError, BadRequest, NotFound, RateLimited, Upstream
from tests.helpers import SUPABASE_URL, client_for, make_app, make_settings

USER = str(uuid4())
SESSION = {
    "access_token": "access",
    "refresh_token": "refresh",
    "expires_at": 1800000000,
    "expires_in": 3600,
    "token_type": "bearer",
    "user": {"id": USER, "email": "a@b.test", "app_metadata": {"x": 1}},
}


class Replies:
    """Records each request and answers with the next prepared reply."""

    def __init__(self, *replies: httpx.Response | Exception):
        self.replies = list(replies)
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply

    def body(self, index: int = 0) -> dict:
        return json.loads(self.requests[index].content or b"null")


def gotrue(*replies, **settings) -> tuple[GoTrue, Replies]:
    upstream = Replies(*replies)
    http = httpx.AsyncClient(transport=httpx.MockTransport(upstream))
    return GoTrue(make_settings(**settings), http, lambda: 1_000_000), upstream


async def test_otp_forces_create_user_and_sends_only_the_email():
    auth, up = gotrue(httpx.Response(200, json={}))
    await auth.send_otp("a@b.test")
    request = up.requests[0]
    assert request.url == f"{SUPABASE_URL}/auth/v1/otp"
    assert up.body() == {"email": "a@b.test", "create_user": True}
    assert request.headers["apikey"] == "anon-key"


async def test_verify_forces_type_email():
    auth, up = gotrue(httpx.Response(200, json=SESSION))
    session = await auth.verify("a@b.test", "123456")
    assert up.requests[0].url == f"{SUPABASE_URL}/auth/v1/verify"
    assert up.body() == {"email": "a@b.test", "token": "123456", "type": "email"}
    # Only the whitelisted session fields come back. The Supabase user object stays behind.
    assert session == {
        "access_token": "access",
        "refresh_token": "refresh",
        "expires_at": 1800000000,
        "user": {"id": USER},
    }


async def test_expires_at_is_computed_when_missing():
    reply = {k: v for k, v in SESSION.items() if k != "expires_at"}
    auth, _ = gotrue(httpx.Response(200, json=reply))
    assert (await auth.verify("a@b.test", "123456"))["expires_at"] == 1_000_000 + 3600


async def test_refresh_uses_the_refresh_grant():
    auth, up = gotrue(httpx.Response(200, json=SESSION))
    await auth.refresh("tok")
    assert up.requests[0].url.params["grant_type"] == "refresh_token"
    assert up.body() == {"refresh_token": "tok"}


async def test_id_token_forwards_only_the_four_fields():
    auth, up = gotrue(httpx.Response(200, json=SESSION), httpx.Response(200, json=SESSION))
    await auth.id_token("google", "idt", "acc", "n")
    assert up.requests[0].url.params["grant_type"] == "id_token"
    assert up.body(0) == {
        "provider": "google",
        "id_token": "idt",
        "access_token": "acc",
        "nonce": "n",
    }
    await auth.id_token("apple", "idt", None, None)
    assert up.body(1) == {"provider": "apple", "id_token": "idt"}


@pytest.mark.parametrize(
    ("call", "status", "error"),
    [
        ("otp", 422, BadRequest),
        ("otp", 429, RateLimited),
        ("otp", 500, Upstream),
        ("otp", 401, Upstream),  # the gateway refused our API key: our mistake, not the user's
        ("verify", 403, BadRequest),
        ("verify", 400, BadRequest),
        ("verify", 502, Upstream),
        ("refresh", 400, BadRequest),
        ("id_token", 400, BadRequest),
    ],
)
async def test_errors_map_to_ours(call, status, error):
    auth, _ = gotrue(httpx.Response(status, json={"msg": "secret detail"}))
    with pytest.raises(error) as caught:
        if call == "otp":
            await auth.send_otp("a@b.test")
        elif call == "verify":
            await auth.verify("a@b.test", "123456")
        elif call == "refresh":
            await auth.refresh("tok")
        else:
            await auth.id_token("google", "idt", None, None)
    assert "secret detail" not in caught.value.message


async def test_error_codes():
    auth, _ = gotrue(httpx.Response(403, json={"error_code": "otp_expired"}))
    with pytest.raises(BadRequest) as caught:
        await auth.verify("a@b.test", "123456")
    assert caught.value.code == "otp_invalid"
    auth, _ = gotrue(httpx.Response(400, json={"error_code": "refresh_token_not_found"}))
    with pytest.raises(BadRequest) as caught:
        await auth.refresh("tok")
    assert caught.value.code == "refresh_invalid"
    auth, _ = gotrue(
        httpx.Response(400, json={"error_code": "bad_id_token", "msg": "Bad ID token"})
    )
    with pytest.raises(BadRequest) as caught:
        await auth.id_token("google", "idt", None, None)
    assert caught.value.code == "id_token_invalid"


async def test_a_disabled_provider_is_404():
    reply = httpx.Response(400, json={"msg": "Unsupported provider: provider is not enabled"})
    auth, _ = gotrue(reply)
    with pytest.raises(NotFound) as caught:
        await auth.id_token("google", "idt", None, None)
    assert caught.value.code == "provider_disabled"


async def test_network_failure_is_502():
    auth, _ = gotrue(httpx.ConnectError("down"), httpx.ReadTimeout("slow"))
    for call in (lambda: auth.send_otp("a@b.test"), lambda: auth.refresh("tok")):
        with pytest.raises(Upstream):
            await call()


async def test_a_session_we_cannot_read_is_502():
    auth, _ = gotrue(httpx.Response(200, json={"access_token": "only"}))
    with pytest.raises(Upstream):
        await auth.verify("a@b.test", "123456")


async def test_not_set_up_is_502_and_makes_no_call():
    auth, up = gotrue(supabase_url="")
    with pytest.raises(Upstream):
        await auth.send_otp("a@b.test")
    assert up.requests == []


async def test_logout_is_local_and_a_gone_session_counts_as_done():
    auth, up = gotrue(httpx.Response(401, json={"error_code": "session_not_found"}))
    await auth.logout("the-access-token")
    request = up.requests[0]
    assert request.url.params["scope"] == "local"
    assert request.headers["authorization"] == "Bearer the-access-token"
    auth, _ = gotrue(httpx.Response(503))
    with pytest.raises(Upstream):
        await auth.logout("t")


async def test_delete_user_uses_the_service_key_and_404_counts_as_done():
    auth, up = gotrue(httpx.Response(200, json={}), httpx.Response(404, json={}))
    user = uuid4()
    await auth.delete_user(user)
    request = up.requests[0]
    assert request.method == "DELETE"
    assert request.url.path == f"/auth/v1/admin/users/{user}"
    assert request.headers["apikey"] == "service-key"
    await auth.delete_user(user)  # 404: already gone


async def test_delete_user_failure_is_502():
    auth, _ = gotrue(httpx.Response(500))
    with pytest.raises(Upstream):
        await auth.delete_user(uuid4())
    auth, _ = gotrue(supabase_service_role_key="")
    with pytest.raises(ApiError):
        await auth.delete_user(uuid4())


# --- the routes -------------------------------------------------------------


async def test_routes_reject_unknown_fields_and_hide_the_provider_when_off():
    up = Replies(httpx.Response(200, json=SESSION))
    app = make_app(make_settings(auth_providers="email"), up)
    async with client_for(app) as client:
        reply = await client.post(
            "/v1/auth/verify", json={"email": "a@b.test", "code": "123456", "type": "x"}
        )
        assert reply.status_code == 422
        assert reply.json()["error"]["code"] == "invalid_request"
        assert all(set(item) == {"loc", "type"} for item in reply.json()["error"]["detail"])
        assert "123456" not in reply.text  # the input is never echoed
        reply = await client.post("/v1/auth/id-token", json={"provider": "google", "id_token": "t"})
        assert reply.status_code == 404
        assert reply.json()["error"]["code"] == "provider_disabled"
    assert up.requests == []


async def test_otp_route_is_204_and_rate_limited_per_email():
    up = Replies(*[httpx.Response(200, json={})] * 20)
    async with client_for(make_app(handler=up)) as client:
        for _ in range(10):
            assert (
                await client.post("/v1/auth/otp", json={"email": "A@B.test"})
            ).status_code == 204
        reply = await client.post("/v1/auth/otp", json={"email": "a@b.test"})
        assert reply.status_code == 429
        assert int(reply.headers["retry-after"]) >= 1
        assert reply.json()["error"]["code"] == "rate_limited"
    assert up.body(0)["email"] == "a@b.test"


async def test_verify_route_returns_a_session():
    up = Replies(httpx.Response(200, json=SESSION))
    async with client_for(make_app(handler=up)) as client:
        reply = await client.post("/v1/auth/verify", json={"email": "a@b.test", "code": "123456"})
    assert reply.status_code == 200
    assert reply.json() == {
        "access_token": "access",
        "refresh_token": "refresh",
        "expires_at": 1800000000,
        "user": {"id": USER},
    }
