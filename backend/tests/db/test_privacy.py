"""The privacy rules, tried against a real database.

The canary test seeds dates, memos, and other diary text that nobody else may
ever see. Then it calls every route another person can reach and checks that
none of it comes back.
"""

import json

from app.logic.match import match_score
from tests.db.conftest import film, stub, today, wish

CANARIES = [
    "1999-12-31",
    "1987-06-05",
    "1988-08-08",
    "1999-11-11",
    "CANARY-MEMO",
    "CANARY-PLACE",
    "CANARY-WITH",
    "CANARY-TAG",
    "CANARY-FILM",
    "CANARY-SEAT",
    "999.5",
]
BANNED_KEYS = {
    "created",
    "memo",
    "place",
    "seat",
    "price",
    "with",
    "tags",
    "no",
    "planned",
    "added",
    "date",
    "watched_on",
    "created_at",
    "updated_at",
    "deleted_at",
}


async def seed(world):
    """Olive shares with friends. Fred is her friend. Sam is a stranger. Bob was blocked."""
    olive = await world.user("olive", visibility="friends", share_ratings=True)
    fred = await world.user("fred", visibility="friends")
    sam = await world.user("sam")
    bob = await world.user("bob", visibility="friends")
    await world.friends(olive, fred)
    await world.friends(olive, bob)
    await olive.ok("post", "/v1/blocks", {"user_id": str(bob.id)}, status=204)
    canary = {
        "memo": "CANARY-MEMO",
        "place": "CANARY-PLACE",
        "seat": "CANARY-SEAT",
        "price": 999.5,
        "tags": ["CANARY-TAG"],
        "with": "CANARY-WITH",
    }
    old = stub(
        "old", "Q949228", date="1999-12-31", rating=4.5, created="1987-06-05T03:04:05.000", **canary
    )
    fresh = stub("fresh", "Q2", date=today(), rating=3.0, **canary)
    fresh["film"] = {**film("Q2"), "memo": "CANARY-FILM", "created": "1987-06-05"}
    hidden = stub("hidden", "Q30", date=today(), rating=5.0, private=True, **canary)
    wishes = wish("Q4", added="1988-08-08T08:08:08.000", planned="1999-11-11")
    await olive.push(old, fresh, hidden, wishes)
    await fred.push(
        stub("f1", "Q949228", date=today(), rating=2.0),
        stub("f3", "Q3", date=today(), private=True),
    )
    await bob.push(stub("b1", "Q949228", date=today(), rating=1.0))
    return olive, fred, sam, bob


def routes(owner):
    return [
        (f"/v1/users/{owner.id}", {}),
        (f"/v1/users/{owner.id}/films", {}),
        ("/v1/films/Q949228/friends", {}),
        ("/v1/films/Q2/friends", {}),
        ("/v1/films/Q30/friends", {}),
        ("/v1/feed", {}),
        ("/v1/friends", {}),
        ("/v1/friends/requests", {}),
        ("/v1/users/lookup", {"handle": "olive"}),
        ("/v1/blocks", {}),
    ]


def _expected(actor: str, owner, path: str) -> int:
    """The status each actor must get. Anything else fails the sweep.

    The profile and its shelf answer 404 to a stranger and to a blocked user,
    the same as for a missing profile. The lookup hides a block behind that 404
    too (its 30/hour limit is per actor and untouched). The watcher list and the
    feed answer 200 with an empty list instead of leaking by status.
    """
    if path == f"/v1/users/{owner.id}/films":
        # Your own shelf is not served: the phone builds it from the diary.
        return 404 if actor == "olive" else _profile_status(actor)
    if path == f"/v1/users/{owner.id}":
        return _profile_status(actor)
    if path == "/v1/users/lookup":
        # Nobody finds themselves by handle, and a block reads as "no such handle".
        return 404 if actor in ("olive", "bob") else 200
    return 200


def _profile_status(actor: str) -> int:
    """A friend sees the profile; a stranger and a blocked user get a 404."""
    return 200 if actor in ("olive", "fred") else 404


def all_keys(value) -> set[str]:
    if isinstance(value, dict):
        return set(value) | {k for v in value.values() for k in all_keys(v)}
    if isinstance(value, list):
        return {k for v in value for k in all_keys(v)}
    return set()


async def sweep(client, owner) -> dict[str, tuple[int, str]]:
    """Every route another person can reach, with the status it must answer."""
    found = {}
    for path, params in routes(owner):
        reply = await client.get(path, **params)
        found[path] = (reply.status_code, reply.text)
    return found


async def test_canary_dates_and_memos_never_reach_another_person(world):
    olive, fred, sam, bob = await seed(world)
    group = await world.group(olive, "Crew", fred, sam)
    gid = group["id"]
    await olive.ok("put", f"/v1/groups/{gid}/films/Q949228", {"film": film()}, status=204)
    await olive.ok(
        "put", f"/v1/groups/{gid}/swipes", {"swipes": [{"film_id": "Q2", "vote": "seen"}]}
    )
    for actor in (olive, fred, sam, bob):
        seen = await sweep(actor, olive)
        for path, (status, text) in seen.items():
            # A route that broke (500) is a failure whether or not it leaks.
            assert status == _expected(actor.name, olive, path), (actor.name, path, text[:200])
            for canary in CANARIES:
                assert canary not in text, f"{actor.name} got {canary!r} from {path}"
            if status == 200:
                assert not all_keys(json.loads(text)) & BANNED_KEYS, (actor.name, path)
    for actor in (fred, sam):
        for path in (
            f"/v1/groups/{gid}",
            f"/v1/groups/{gid}/deck",
            f"/v1/groups/{gid}/deck-inputs",
            f"/v1/groups/{gid}/films",
            f"/v1/groups/{gid}/tallies",
            f"/v1/groups/{gid}/messages",
            f"/v1/groups/{gid}/nights",
        ):
            reply = await actor.get(path)
            assert reply.status_code == 200, path
            for canary in CANARIES:
                assert canary not in reply.text, f"{actor.name} got {canary!r} from {path}"


async def test_what_a_friend_sees(world):
    olive, fred, *_ = await seed(world)
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    assert (profile["relation"], profile["visible"]) == ("friend", True)
    stats = profile["stats"]
    assert (stats["films"], stats["viewings"], stats["avg_rating"]) == (2, 2, 3.75)
    assert (stats["top_genres"], stats["top_langs"]) == (["action", "drama"], ["kn"])
    assert [t["film_id"] for t in profile["top_films"]] == ["Q949228", "Q2"]  # ratings shared
    assert [w["film_id"] for w in profile["watchlist"]] == ["Q4"]
    shelf = await fred.ok("get", f"/v1/users/{olive.id}/films")
    assert [i["film_id"] for i in shelf["items"]] == ["Q2", "Q949228"]  # newest watch first
    assert shelf["next_cursor"] is None
    feed = await fred.ok("get", "/v1/feed")
    assert [(i["kind"], i["film_id"], i["user"]["handle"]) for i in feed["items"]] == [
        ("watched", "Q2", "olive")
    ]
    assert feed["items"][0]["id"].startswith("w:")
    watchers = await fred.ok("get", "/v1/films/Q949228/friends")
    assert [(w["user"]["handle"], w["rating"]) for w in watchers["items"]] == [("olive", 4.5)]
    assert (await fred.ok("get", "/v1/films/Q30/friends"))["items"] == []


async def test_a_trait_a_film_lists_twice_counts_once(world):
    olive = await world.user("olive", visibility="friends", share_ratings=True)
    fred = await world.user("fred", visibility="friends")
    await world.friends(olive, fred)
    first = stub("one", "Q949228", date=today())  # action, drama
    twice = stub("two", "Q2", date=today())
    twice["film"] = {**film("Q2"), "g": ["action", "action"], "l": ["kn", "kn"]}
    third = stub("three", "Q3", date=today())
    third["film"] = {**film("Q3"), "g": ["drama"], "l": ["hi"]}
    await olive.push(first, twice, third)
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    stats = profile["stats"]
    # Once per film, not once per entry: action and drama are level at two films,
    # and the duplicate "action" must not push drama out of the top three.
    assert (stats["films"], stats["viewings"]) == (3, 3)
    assert stats["top_genres"] == ["action", "drama"]
    assert stats["top_langs"] == ["hi", "kn"]


async def test_a_private_stub_is_nowhere(world):
    olive, fred, *_ = await seed(world)
    group = await world.group(olive, "Crew", fred)
    gid = group["id"]
    friend_view = await fred.ok("get", f"/v1/users/{olive.id}/films")
    assert "Q30" not in json.dumps(friend_view)
    assert "Q30" not in json.dumps(await fred.ok("get", "/v1/feed"))
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    assert "Q30" not in json.dumps(profile)
    assert profile["stats"]["viewings"] == 2
    inputs = await fred.ok("get", f"/v1/groups/{gid}/deck-inputs")
    assert "Q30" not in inputs["seen"]
    assert {"Q949228", "Q2", "Q3"} <= set(inputs["seen"])  # Fred's own private Q3 counts for Fred
    mine = await olive.ok("get", f"/v1/groups/{gid}/deck-inputs")
    assert {"Q949228", "Q2", "Q30"} <= set(mine["seen"])  # Olive's own private Q30 counts for Olive
    assert "Q3" not in mine["seen"]  # Fred's private stub does not leak to Olive


async def test_match_counts_my_private_films_and_ignores_ratings_i_may_not_see(world):
    olive, fred, *_ = await seed(world)
    # Olive public: Q949228 (4.5), Q2 (3.0). Fred: Q949228 (2.0) and a private Q3.
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    expected = match_score(2, 2, [(2.0, 4.5)], True)
    assert profile["match"] == {"both": expected.both, "pct": expected.pct}
    listed = await fred.ok("get", "/v1/friends")
    assert listed["items"][0]["match"] == profile["match"]
    # Fred's own private stub of Olive's public Q2 counts for the match.
    await fred.push(stub("f4", "Q2", private=True, rating=3.0))
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    assert profile["match"]["both"] == 2
    # Olive hides ratings: her ratings no longer enter the score.
    await olive.ok("patch", "/v1/me", {"share_ratings": False})
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    expected = match_score(3, 2, [(2.0, None), (3.0, None)], False)
    assert profile["match"] == {"both": expected.both, "pct": expected.pct}


async def test_ratings_only_if_allowed(world):
    olive, fred, *_ = await seed(world)
    await olive.ok("patch", "/v1/me", {"share_ratings": False})
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    assert profile["stats"]["avg_rating"] is None
    assert all(t["rating"] is None for t in profile["top_films"])
    shelf = await fred.ok("get", f"/v1/users/{olive.id}/films")
    assert all(i["rating"] is None for i in shelf["items"])
    feed = await fred.ok("get", "/v1/feed")
    assert all(i["rating"] is None for i in feed["items"])
    watchers = await fred.ok("get", "/v1/films/Q949228/friends")
    assert all(w["rating"] is None for w in watchers["items"])
    await olive.ok("patch", "/v1/me", {"share_ratings": True})
    shelf = await fred.ok("get", f"/v1/users/{olive.id}/films")
    assert {i["film_id"]: i["rating"] for i in shelf["items"]} == {"Q2": 3.0, "Q949228": 4.5}
    # Without shared ratings the top films order by viewings, then recency.
    await olive.ok("patch", "/v1/me", {"share_ratings": False})
    profile = await fred.ok("get", f"/v1/users/{olive.id}")
    assert [t["film_id"] for t in profile["top_films"]] == ["Q2", "Q949228"]


async def test_new_profiles_are_private_until_the_owner_opens_them(world):
    newbie = await world.user("newbie")  # visibility defaults to private
    fred = await world.user("fred", visibility="friends")
    await world.friends(newbie, fred)
    await newbie.push(stub("n1", "Q949228", date=today(), rating=5.0))
    assert (await fred.get(f"/v1/users/{newbie.id}")).status_code == 404
    assert (await fred.get(f"/v1/users/{newbie.id}/films")).status_code == 404
    assert (await fred.ok("get", "/v1/feed"))["items"] == []
    assert (await fred.ok("get", "/v1/films/Q949228/friends"))["items"] == []
    listed = (await fred.ok("get", "/v1/friends"))["items"]
    assert [(i["card"]["handle"], i["visible"], i["match"]) for i in listed] == [
        ("newbie", False, None)
    ]
    await newbie.ok("patch", "/v1/me", {"visibility": "friends"})
    assert (await fred.get(f"/v1/users/{newbie.id}")).status_code == 200
    assert len((await fred.ok("get", "/v1/feed"))["items"]) == 1


async def test_a_stranger_sees_a_card_and_nothing_else(world):
    olive, _, sam, _ = await seed(world)
    seen = await sweep(sam, olive)
    assert seen[f"/v1/users/{olive.id}"][0] == 404
    assert seen[f"/v1/users/{olive.id}/films"][0] == 404
    for path in ("/v1/films/Q949228/friends", "/v1/feed", "/v1/friends"):
        assert json.loads(seen[path][1])["items"] == []
    lookup = json.loads(seen["/v1/users/lookup"][1])
    assert lookup["relation"] == "none"
    assert set(lookup["card"]) == {"id", "handle", "display_name", "avatar_color"}


async def test_blocked_means_invisible_both_ways(world):
    olive, _, _, bob = await seed(world)
    for actor, target in ((bob, olive), (olive, bob)):
        assert (await actor.get("/v1/users/lookup", handle=target.name)).status_code == 404
        assert (await actor.get(f"/v1/users/{target.id}")).status_code == 404
        assert (await actor.get(f"/v1/users/{target.id}/films")).status_code == 404
        sent = await actor.post("/v1/friends/requests", {"user_id": str(target.id)})
        assert sent.status_code == 404
    assert (await bob.ok("get", "/v1/friends"))["items"] == []
    assert (await bob.ok("get", "/v1/feed"))["items"] == []
    assert (await bob.ok("get", "/v1/films/Q949228/friends"))["items"] == []
    olive_feed = await olive.ok("get", "/v1/feed")
    assert all(item["user"]["handle"] != "bob" for item in olive_feed["items"])
    watchers = await olive.ok("get", "/v1/films/Q949228/friends")
    assert [w["user"]["handle"] for w in watchers["items"]] == ["fred"]


async def test_my_own_profile_is_shown_as_friends_see_it(world):
    olive, *_ = await seed(world)
    mine = await olive.ok("get", f"/v1/users/{olive.id}")
    assert (mine["relation"], mine["visible"], mine["match"]) == ("self", True, None)
    assert mine["stats"]["films"] == 2  # the private stub is left out
    assert "Q30" not in json.dumps(mine)
    await olive.ok("patch", "/v1/me", {"share_ratings": False, "visibility": "private"})
    mine = await olive.ok("get", f"/v1/users/{olive.id}")
    assert mine["visible"] is False
    assert mine["stats"]["avg_rating"] is None
    assert (
        await olive.get(f"/v1/users/{olive.id}/films")
    ).status_code == 404  # the app builds it locally


async def test_a_reaction_needs_a_film_i_may_see_and_shows_up_for_the_owner(world):
    olive, fred, sam, _ = await seed(world)
    ok = await fred.put("/v1/reactions", {"user_id": str(olive.id), "film_id": "Q2", "reaction": 3})
    assert ok.status_code == 204
    for film_id, actor in (
        ("Q30", fred),
        ("Q4", fred),
        ("Q2", sam),
    ):  # private, never watched, stranger
        denied = await actor.put(
            "/v1/reactions", {"user_id": str(olive.id), "film_id": film_id, "reaction": 1}
        )
        assert denied.status_code == 404, (film_id, actor.name)
    bad = await fred.put(
        "/v1/reactions", {"user_id": str(olive.id), "film_id": "Q2", "reaction": 8}
    )
    assert bad.status_code == 422
    feed = await olive.ok("get", "/v1/feed")
    reactions = [i for i in feed["items"] if i["kind"] == "reaction"]
    assert [(i["film_id"], i["reaction"], i["user"]["handle"], i["id"][:2]) for i in reactions] == [
        ("Q2", 3, "fred", "r:")
    ]
    watched = await fred.ok("get", "/v1/feed")
    assert [i["my_reaction"] for i in watched["items"]] == [3]
    first = reactions[0]["id"]
    await fred.ok(
        "put",
        "/v1/reactions",
        {"user_id": str(olive.id), "film_id": "Q2", "reaction": 5},
        status=204,
    )
    again = [i for i in (await olive.ok("get", "/v1/feed"))["items"] if i["kind"] == "reaction"]
    assert again[0]["reaction"] == 5 and again[0]["id"] != first  # a new reaction moves to the top
    await fred.ok(
        "put",
        "/v1/reactions",
        {"user_id": str(olive.id), "film_id": "Q2", "reaction": None},
        status=204,
    )
    assert [
        i for i in (await olive.ok("get", "/v1/feed"))["items"] if i["kind"] == "reaction"
    ] == []
