"""Check Supabase access tokens locally.

The key comes from the token header `alg`:
- ES256, RS256: the project JWKS, cached. An unknown `kid` triggers a refetch,
  at most one per minute.
- HS256: the shared secret, only when SUPABASE_JWT_SECRET is set.
- anything else, including `none`: refused.

A token needs `exp`, `aud` = authenticated, `iss` = <SUPABASE_URL>/auth/v1, a
UUID `sub`, `role` = authenticated, and must not be anonymous.
"""

import asyncio
import logging
import time
from collections.abc import Callable
from typing import Any
from uuid import UUID

import httpx
import jwt

from app.errors import Unauthorized, Upstream
from app.settings import Settings

log = logging.getLogger("talkies")

_KEY_TYPES = {"ES256": "EC", "RS256": "RSA"}
_REFETCH_AFTER = 60.0
_LEEWAY = 10  # seconds of clock skew, also for a fresh token whose `iat` is ahead of this host


class Verifier:
    def __init__(
        self,
        settings: Settings,
        http: httpx.AsyncClient,
        clock: Callable[[], float] = time.monotonic,
    ):
        self._issuer = settings.issuer
        self._jwks_url = f"{settings.issuer}/.well-known/jwks.json"
        self._anon_key = settings.supabase_anon_key
        self._secret = settings.supabase_jwt_secret
        self._http = http
        self._clock = clock
        self._keys: dict[str, tuple[str, Any]] = {}  # kid -> (JWK kty, key object)
        self._fetched_at: float | None = None
        self._failed = False
        self._lock = asyncio.Lock()

    async def verify(self, token: str) -> UUID:
        """Return the user id of a valid access token, or raise Unauthorized."""
        try:
            header = jwt.get_unverified_header(token)
        except jwt.PyJWTError as exc:
            raise Unauthorized() from exc
        alg = header.get("alg")
        # The allowlist is fixed, never taken from the token header. ES256/RS256
        # always verify against the JWKS; HS256 only when the shared secret is
        # configured, and then only with the secret. The two paths never mix.
        if alg == "HS256":
            if not self._secret:
                raise Unauthorized()
            key, algs = self._secret, ["HS256"]
        elif alg in _KEY_TYPES:
            key, algs = await self._key(alg, header.get("kid")), list(_KEY_TYPES)
        else:
            raise Unauthorized()
        try:
            claims = jwt.decode(
                token,
                key,
                algorithms=algs,
                audience="authenticated",
                issuer=self._issuer,
                leeway=_LEEWAY,
                options={"require": ["exp", "aud", "iss", "sub"]},
            )
        except jwt.PyJWTError as exc:
            raise Unauthorized() from exc
        return _subject(claims)

    async def _key(self, alg: str, kid: Any) -> Any:
        if alg == "HS256":
            if not self._secret:
                raise Unauthorized()
            return self._secret
        if alg not in _KEY_TYPES or not isinstance(kid, str):
            raise Unauthorized()
        entry = self._keys.get(kid)
        if entry is None:
            await self._refetch()
            entry = self._keys.get(kid)
        if entry is None:
            # An unreachable JWKS is not the user's fault: answer 502, not 401.
            raise Upstream() if self._failed else Unauthorized()
        kty, key = entry
        if kty != _KEY_TYPES[alg]:
            raise Unauthorized()
        return key

    async def _refetch(self) -> None:
        """Load the JWKS. At most once per minute, however many requests wait."""
        # ponytail: keys stay cached until a token with an unknown kid arrives, so a revoked
        # key is trusted until then (tokens last 1 hour). Add a TTL refetch if that matters.
        async with self._lock:
            now = self._clock()
            if self._fetched_at is not None and now - self._fetched_at < _REFETCH_AFTER:
                return
            self._fetched_at = now
            try:
                self._keys = await self._load()
                self._failed = False
            except Exception as exc:  # network, bad status, or bad JSON
                self._failed = True
                log.warning("jwks fetch failed: %s", type(exc).__name__)

    async def _load(self) -> dict[str, tuple[str, Any]]:
        headers = {"apikey": self._anon_key} if self._anon_key else {}
        reply = await self._http.get(self._jwks_url, headers=headers, timeout=8.0)
        reply.raise_for_status()
        keys: dict[str, tuple[str, Any]] = {}
        for jwk in reply.json()["keys"]:
            try:
                keys[jwk["kid"]] = (jwk["kty"], jwt.PyJWK.from_dict(jwk).key)
            except (KeyError, jwt.PyJWTError):
                log.warning("jwks: skipped a key it cannot use")
        return keys


def _subject(claims: dict[str, Any]) -> UUID:
    if claims.get("role") != "authenticated" or claims.get("is_anonymous"):
        raise Unauthorized()
    try:
        return UUID(str(claims["sub"]))
    except (KeyError, ValueError) as exc:
        raise Unauthorized() from exc
