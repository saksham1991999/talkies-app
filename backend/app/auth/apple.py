"""Sign in with Apple: token exchange and revocation (App Store rule 4.8).

When a user signs in with Apple, the phone also sends the authorization code
that Apple returned. We exchange that code with Apple for a refresh token and
store it on the profile. When the user deletes the account, we send that
refresh token to Apple's revoke endpoint, so Apple stops treating the app as
authorized.

Nothing here may break a sign-in or a deletion: a failed exchange or revoke is
logged and skipped. Without APPLE_CLIENT_ID and APPLE_CLIENT_SECRET the whole
module steps aside, so local dev needs no Apple setup.
"""

import logging
from uuid import UUID

import httpx

from app.common import user_color
from app.settings import Settings

log = logging.getLogger("talkies")

TOKEN_URL = "https://appleid.apple.com/auth/token"
REVOKE_URL = "https://appleid.apple.com/auth/revoke"
TIMEOUT = httpx.Timeout(8.0)


class Apple:
    def __init__(self, settings: Settings, http: httpx.AsyncClient):
        self._client_id = settings.apple_client_id
        self._secret = settings.apple_client_secret
        self._http = http

    @property
    def configured(self) -> bool:
        return bool(self._client_id and self._secret)

    async def exchange(self, code: str) -> str | None:
        """Trade an authorization code for the user's Apple refresh token.

        Returns None (and logs) on any failure. A sign-in must not fail because
        revocation later would not be possible.
        """
        if not self.configured:
            return None
        try:
            reply = await self._http.post(
                TOKEN_URL,
                data={
                    "client_id": self._client_id,
                    "client_secret": self._secret,
                    "code": code,
                    "grant_type": "authorization_code",
                },
                timeout=TIMEOUT,
            )
            if reply.status_code >= 400:
                log.warning("apple token endpoint answered %s", reply.status_code)
                return None
            token = reply.json().get("refresh_token")
            return str(token) if token else None
        except (httpx.HTTPError, ValueError) as exc:
            log.warning("apple token exchange failed: %s", type(exc).__name__)
            return None

    async def revoke(self, refresh_token: str) -> None:
        """Revoke the Apple grant. Raises on failure; the caller decides."""
        reply = await self._http.post(
            REVOKE_URL,
            data={
                "client_id": self._client_id,
                "client_secret": self._secret,
                "token": refresh_token,
                "token_type_hint": "refresh_token",
            },
            timeout=TIMEOUT,
        )
        if reply.status_code >= 400:
            log.warning("apple revoke endpoint answered %s", reply.status_code)
            raise RuntimeError(f"apple revoke answered {reply.status_code}")


async def save_refresh_token(apple: Apple, db, code: str, user: UUID) -> None:
    """Exchange a sign-in code and keep the refresh token on the profile.

    A failure is logged, never raised: the user is signed in either way.
    """
    try:
        token = await apple.exchange(code)
        if token is None:
            return
        async with db.tx() as c:
            await c.execute(SAVE, user, token, user_color(user))
    except Exception as exc:
        log.warning("storing the apple refresh token failed: %s", type(exc).__name__)


SAVE = """
insert into profiles (id, apple_refresh_token, avatar_color) values ($1, $2, $3)
on conflict (id) do update set apple_refresh_token = excluded.apple_refresh_token
"""


async def revoke_or_log(apple: Apple, refresh_token: str | None) -> None:
    """Best-effort revoke on account deletion. Never raises; every outcome is logged."""
    if refresh_token is None:
        log.info("apple revoke skipped: the account never stored an apple refresh token")
        return
    if not apple.configured:
        log.info("apple revoke skipped: no apple credentials configured")
        return
    try:
        await apple.revoke(refresh_token)
        log.info("apple grant revoked on account deletion")
    except Exception as exc:
        log.warning("apple revoke failed; the deletion proceeds: %s", type(exc).__name__)
