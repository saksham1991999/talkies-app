"""A sliding-window rate limiter that lives in process memory.

Run uvicorn with --proxy-headers and --forwarded-allow-ips, or every client
looks like the proxy and shares one IP bucket.
"""

import logging
import math
import time
from collections import deque
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, Request

from app.errors import RateLimited

log = logging.getLogger("talkies")

# Addresses allowed to sit in front of the server and set X-Forwarded-For.
# The Dockerfile runs uvicorn with --forwarded-allow-ips for exactly these.
_TRUSTED_PROXIES = {"127.0.0.1", "::1", "172.17.0.1"}

# rule name -> (hits allowed, window in seconds)
RULES: dict[str, tuple[int, float]] = {
    "otp_ip": (30, 3600),
    "otp_email": (10, 3600),
    "verify_ip": (30, 3600),
    # Sign in with Google or Apple: unauthenticated, so it needs its own bucket
    # like the other sign-in routes. 30 per hour matches otp_ip.
    "id_token_ip": (30, 3600),
    "lookup": (30, 3600),
    "join": (10, 3600),
    "friend_request": (30, 3600),
    "message": (30, 60),
    "send_film": (30, 3600),
    "report": (20, 3600),
    # Token refresh: every device refreshes about once an hour, so 60 per 5
    # minutes leaves room for many devices behind one address.
    "refresh_ip": (60, 300),
    # Keyed per (group, user) in the routers, so one member cannot starve the rest.
    "deck": (1, 10),
}

_LONGEST_WINDOW = max(window for _, window in RULES.values())
_SWEEP_EVERY = 1000


class Limiter:
    # ponytail: per process. Two instances allow twice the limit. Move the hits
    # to Redis or a Postgres table before running more than one instance.
    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self._clock = clock
        self._hits: dict[tuple[str, str], deque[float]] = {}
        self._calls = 0

    def check(self, rule: str, key: str) -> None:
        """Count one hit. Raise RateLimited when the window is full."""
        limit, window = RULES[rule]
        now = self._clock()
        hits = self._hits.setdefault((rule, key), deque())
        while hits and hits[0] <= now - window:
            hits.popleft()
        if len(hits) >= limit:
            raise RateLimited(math.ceil(hits[0] + window - now))
        hits.append(now)
        self._calls += 1
        if self._calls % _SWEEP_EVERY == 0:
            self._sweep(now)

    def _sweep(self, now: float) -> None:
        stale = [k for k, h in self._hits.items() if not h or h[-1] <= now - _LONGEST_WINDOW]
        for key in stale:
            del self._hits[key]


def get_limiter(request: Request) -> Limiter:
    return request.app.state.limiter


LimiterDep = Annotated[Limiter, Depends(get_limiter)]


def client_ip(request: Request) -> str:
    """The address the limit is counted against. It fails closed.

    The server runs behind a proxy (see the Dockerfile: uvicorn --proxy-headers),
    so uvicorn rewrites `request.client` from X-Forwarded-For when the socket
    peer is trusted. Uvicorn leaves the header on the request, so its presence
    alone proves nothing: the rewrite is what makes the header and the socket
    agree. When they disagree the header came from an untrusted peer, the
    proxy-header pass did not run, and every client would share one bucket:
    deny the request and say so loudly instead of silently grouping everyone.

    Uvicorn --proxy-headers with --forwarded-allow-ips='*' (the Dockerfile's
    flags) rewrites `request.client` to the FIRST entry of the chain, while
    the header itself keeps every hop a proxy appended
    ($proxy_add_x_forwarded_for) or a CDN added in front. Compare against
    that first entry so a legitimate multi-hop chain is not refused; when
    the rewrite did not run `host` is the socket peer, which is never the
    first entry of an appended chain, so the check still fails closed.
    """
    host = request.client.host if request.client else None
    forwarded = request.headers.get("x-forwarded-for")
    first = forwarded.split(",")[0].strip() if forwarded is not None else None
    if forwarded is None or host in _TRUSTED_PROXIES or host == first:
        return host or "unknown"
    log.error(
        "x-forwarded-for %r on a request from %s: start uvicorn with "
        "--proxy-headers --forwarded-allow-ips, or the rate limiter cannot "
        "tell clients apart; refusing the request",
        forwarded,
        host,
    )
    raise RateLimited(60)
