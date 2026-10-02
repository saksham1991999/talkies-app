"""The routes of the app against backend/API.md, and the rules every route follows."""

import re
from pathlib import Path

from fastapi.routing import APIRoute

from app.auth.deps import current_user, deleting_user
from tests.helpers import make_app

API = Path(__file__).resolve().parents[2] / "API.md"
PUBLIC = {
    ("GET", "/healthz"),
    ("GET", "/j/{}"),
    ("POST", "/v1/auth/otp"),
    ("POST", "/v1/auth/verify"),
    ("POST", "/v1/auth/refresh"),
    ("POST", "/v1/auth/id-token"),
}


def normal(path: str) -> str:
    return re.sub(r"\{[^}]+\}", "{}", path)


def walk(routes, prefix=""):
    """Every APIRoute with its full path. Newer FastAPI keeps included routers as wrappers."""
    for route in routes:
        inner = getattr(route, "original_router", None)
        if inner is not None:
            yield from walk(inner.routes, prefix + route.include_context.prefix)
        elif isinstance(route, APIRoute):
            yield prefix + route.path, route


def app_routes() -> dict[tuple[str, str], APIRoute]:
    routes = {}
    for path, route in walk(make_app().routes):
        for method in route.methods - {"HEAD", "OPTIONS"}:
            routes[(method, normal(path))] = route
    return routes


def documented() -> set[tuple[str, str]]:
    found = set()
    for line in API.read_text().splitlines():
        match = re.match(r"^\| `(GET|POST|PUT|PATCH|DELETE) (/[^`?]*)", line)
        if match:
            found.add((match.group(1), normal(match.group(2))))
    return found


def dependencies(route: APIRoute) -> set:
    calls, todo = set(), list(route.dependant.dependencies)
    while todo:
        dep = todo.pop()
        calls.add(dep.call)
        todo.extend(dep.dependencies)
    return calls


def test_the_app_has_exactly_the_routes_of_api_md():
    in_app = set(app_routes())
    docs = documented()
    assert len(docs) >= 40
    assert in_app == docs, f"only in the app: {in_app - docs}, only in API.md: {docs - in_app}"


def test_every_route_needs_a_signed_in_user_except_the_public_ones():
    for key, route in app_routes().items():
        deps = dependencies(route)
        # DELETE /v1/me takes the token-only dependency on purpose: deletion
        # removes the auth user first, so the retry that finishes a half-done
        # cleanup has a valid token and no account row left to check.
        needs_user = current_user in deps or deleting_user in deps
        assert needs_user != (key in PUBLIC), key
    for key, route in app_routes().items():
        if key not in PUBLIC and key != ("DELETE", "/v1/me"):
            # Every other signed-in route also proves the account still exists.
            assert current_user in dependencies(route), key


def test_every_json_route_declares_its_response_model():
    for (method, path), route in app_routes().items():
        if path == "/j/{}":
            continue  # the invite page is HTML
        if route.status_code == 204:
            assert route.response_model is None, (method, path)
        else:
            assert route.response_model is not None, (method, path)


def test_documented_status_codes_for_created_things():
    created = {
        ("POST", "/v1/groups"),
        ("POST", "/v1/groups/{}/guests"),
        ("POST", "/v1/groups/{}/nights"),
        ("POST", "/v1/groups/{}/messages"),
        ("POST", "/v1/films/send"),
    }
    no_content = {
        ("POST", "/v1/auth/otp"),
        ("POST", "/v1/auth/logout"),
        ("DELETE", "/v1/me"),
        ("POST", "/v1/friends/requests/{}/accept"),
        ("DELETE", "/v1/friends/requests/{}"),
        ("DELETE", "/v1/friends/{}"),
        ("PUT", "/v1/reactions"),
        ("POST", "/v1/blocks"),
        ("DELETE", "/v1/blocks/{}"),
        ("DELETE", "/v1/groups/{}"),
        ("DELETE", "/v1/groups/{}/members/{}"),
        ("PUT", "/v1/groups/{}/films/{}"),
        ("DELETE", "/v1/groups/{}/films/{}"),
        ("DELETE", "/v1/nights/{}"),
        ("PUT", "/v1/nights/{}/rsvp"),
    }
    routes = app_routes()
    for key in created:
        assert routes[key].status_code == 201, key
    for key in no_content:
        assert routes[key].status_code == 204, key
    others = set(routes) - created - no_content - {("GET", "/j/{}")}
    assert all(routes[key].status_code in {None, 200} for key in others)
