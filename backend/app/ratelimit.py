"""A sliding-window rate limiter that lives in process memory.

The limits are keyed by client IP, so the IP has to be one the client cannot
choose. `client_ip` is where that is decided: X-Forwarded-For is believed only
when the request comes from a proxy in TRUSTED_PROXIES.
"""

import ipaddress
import logging
import math
import time
from collections import deque
from collections.abc import Callable
from functools import lru_cache
from typing import Annotated

from fastapi import Depends, Request

from app.errors import RateLimited
from app.settings import get_settings

log = logging.getLogger("talkies")


@lru_cache
def trusted_networks(spec: str) -> tuple[ipaddress.IPv4Network | ipaddress.IPv6Network, ...]:
    """Parse the comma list of proxy addresses and CIDRs. Bad entries are skipped.

    The spec is the cache key, so changing TRUSTED_PROXIES never serves a stale
    list. A typo drops the hop from the trust set, which fails towards trusting
    less, so the limiter ignores the header rather than believing anybody.
    """
    nets = []
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        try:
            nets.append(ipaddress.ip_network(item, strict=False))
        except ValueError:
            log.error("TRUSTED_PROXIES entry %r is not an address or CIDR; ignored", item)
    return tuple(nets)


def is_trusted_proxy(host: str | None) -> bool:
    """True when the address is one of the proxies this server sits behind."""
    if not host:
        return False
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return False
    return any(address in net for net in trusted_networks(get_settings().trusted_proxies))


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
    """The address the limit is counted against.

    X-Forwarded-For is a list that every hop prepends to, and only the entries a
    trusted proxy appended can be believed: a client can send any header it
    likes, and an appending proxy ($proxy_add_x_forwarded_for) keeps the client's
    text at the front of the chain. So the read walks the chain from the right,
    where the closest proxy wrote last, and returns the first address that is not
    itself a trusted proxy. The leftmost entry is never used; taking it let a
    client send a fresh value per request and get a fresh bucket every time,
    which would defeat the per-IP limits on the sign-in and code-check routes.

    When the socket peer is not a trusted proxy, the header proves nothing and
    is ignored: the peer is the client. That is also what a deployment without
    uvicorn --proxy-headers looks like, and what a direct hit on the container
    looks like, so the limiter stays correct instead of believing the caller.
    """
    host = request.client.host if request.client else None
    if not is_trusted_proxy(host):
        return host or "unknown"
    forwarded = request.headers.get("x-forwarded-for")
    if not forwarded:
        return host or "unknown"
    hops = [item.strip() for item in forwarded.split(",") if item.strip()]
    for hop in reversed(hops):
        if not is_trusted_proxy(hop):
            return hop
    # Every hop is a proxy we trust, so the caller is the far end of the chain.
    return hops[0] if hops else host or "unknown"
