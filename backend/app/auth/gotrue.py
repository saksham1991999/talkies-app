"""A thin proxy to Supabase Auth (GoTrue).

Each method sends a fixed set of body fields. Nothing from the phone goes
through that this module does not name. A GoTrue error body is never passed on.
"""

import logging
import time
from collections.abc import Callable
from typing import Any, NoReturn
from uuid import UUID

import httpx

from app.errors import ApiError, BadRequest, NotFound, RateLimited, Upstream
from app.settings import Settings

log = logging.getLogger("talkies")

TIMEOUT = httpx.Timeout(8.0)


def _headers(key: str) -> dict[str, str]:
    headers = {"apikey": key}
    if key.startswith("eyJ"):  # a legacy JWT key also goes in Authorization
        headers["Authorization"] = f"Bearer {key}"
    return headers


def _error_code(reply: httpx.Response) -> str:
    try:
        return str(reply.json().get("error_code", ""))
    except (ValueError, AttributeError):
        return ""


def _message(reply: httpx.Response) -> str:
    try:
        body = reply.json()
        return str(body.get("msg") or body.get("message") or body.get("error_description") or "")
    except (ValueError, AttributeError):
        return ""


def _fail(reply: httpx.Response, client_error: ApiError) -> NoReturn:
    """Turn a failed GoTrue reply into our error.

    429 stays 429. 5xx, and 401 without an error_code (the gateway refusing our
    API key, a setup mistake), become 502. Other 4xx are the caller's fault.
    """
    status = reply.status_code
    if status == 429:
        raise RateLimited(60)
    if status >= 500 or (status == 401 and not _error_code(reply)):
        log.warning("auth service answered %s", status)
        raise Upstream()
    raise client_error


class GoTrue:
    def __init__(
        self,
        settings: Settings,
        http: httpx.AsyncClient,
        clock: Callable[[], float] = time.time,
    ):
        self._base = f"{settings.base_url}/auth/v1" if settings.base_url else ""
        self._anon = _headers(settings.supabase_anon_key) if settings.supabase_anon_key else {}
        self._service = (
            _headers(settings.supabase_service_role_key)
            if settings.supabase_service_role_key
            else {}
        )
        self._http = http
        self._clock = clock

    async def _send(
        self,
        method: str,
        path: str,
        headers: dict[str, str],
        json: dict | None = None,
        params: dict[str, str] | None = None,
    ) -> httpx.Response:
        if not self._base or not headers:
            raise Upstream("The sign-in service is not set up")
        try:
            return await self._http.request(
                method,
                self._base + path,
                headers=headers,
                json=json,
                params=params,
                timeout=TIMEOUT,
            )
        except httpx.HTTPError as exc:
            log.warning("auth service unreachable: %s", type(exc).__name__)
            raise Upstream() from exc

    async def send_otp(self, email: str) -> None:
        reply = await self._send("POST", "/otp", self._anon, {"email": email, "create_user": True})
        if reply.status_code >= 400:
            _fail(reply, BadRequest("invalid_request", "The email was refused"))

    async def verify(self, email: str, code: str) -> dict:
        body = {"email": email, "token": code, "type": "email"}
        reply = await self._send("POST", "/verify", self._anon, body)
        if reply.status_code >= 400:
            _fail(reply, BadRequest("otp_invalid", "The code is wrong or has expired"))
        return self._session(reply)

    async def refresh(self, refresh_token: str) -> dict:
        reply = await self._send(
            "POST",
            "/token",
            self._anon,
            {"refresh_token": refresh_token},
            {"grant_type": "refresh_token"},
        )
        if reply.status_code >= 400:
            _fail(reply, BadRequest("refresh_invalid", "The refresh token is not valid"))
        return self._session(reply)

    async def id_token(
        self, provider: str, id_token: str, access_token: str | None, nonce: str | None
    ) -> dict:
        body: dict[str, Any] = {"provider": provider, "id_token": id_token}
        if access_token:
            body["access_token"] = access_token
        if nonce:
            body["nonce"] = nonce
        reply = await self._send("POST", "/token", self._anon, body, {"grant_type": "id_token"})
        if reply.status_code >= 400:
            message = _message(reply).lower()
            if "provider" in message and ("not enabled" in message or "disabled" in message):
                _fail(reply, NotFound("provider_disabled", "This sign-in method is off"))
            _fail(reply, BadRequest("id_token_invalid", "The ID token is not valid"))
        return self._session(reply)

    async def logout(self, access_token: str) -> None:
        """End this session only. A session that is already gone counts as done."""
        headers = {**self._anon, "Authorization": f"Bearer {access_token}"}
        reply = await self._send("POST", "/logout", headers, None, {"scope": "local"})
        if reply.status_code >= 500 or reply.status_code == 429:
            _fail(reply, BadRequest())

    async def delete_user(self, user_id: UUID) -> None:
        """Delete the Supabase user with the service key. 404 counts as done."""
        reply = await self._send("DELETE", f"/admin/users/{user_id}", self._service)
        if reply.status_code == 404:
            return
        # Only 2xx means the user is gone. A 3xx (a redirect from a misconfigured
        # or proxied endpoint) would otherwise let the local profile be deleted
        # while the Supabase user survives.
        if not 200 <= reply.status_code < 300:
            log.warning("auth user delete answered %s", reply.status_code)
            raise Upstream("The account could not be removed from the sign-in service")

    def _session(self, reply: httpx.Response) -> dict:
        try:
            body = reply.json()
            expires_at = body.get("expires_at") or int(self._clock()) + int(
                body.get("expires_in", 3600)
            )
            # str() would happily turn a null or a number into a token string.
            # Malformed upstream replies become 502, never a broken session.
            access = body["access_token"]
            refresh = body["refresh_token"]
            if not isinstance(access, str) or not access:
                raise ValueError("bad access_token")
            if not isinstance(refresh, str) or not refresh:
                raise ValueError("bad refresh_token")
            return {
                "access_token": access,
                "refresh_token": refresh,
                "expires_at": int(expires_at),
                "user": {"id": str(UUID(str(body["user"]["id"])))},
            }
        except (ValueError, KeyError, TypeError, AttributeError) as exc:
            log.warning("auth service sent a session we cannot read")
            raise Upstream() from exc
