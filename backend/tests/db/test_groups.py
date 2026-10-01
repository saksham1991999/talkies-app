"""Groups, guests, the shared list, the deck, swipes."""

import json
import re
from datetime import UTC, datetime, timedelta
from uuid import UUID

from tests.db.conftest import film, stub, today, wish

CODE = re.compile(r"^[A-HJ-KM-NP-Z2-9]{8}$")
SOMEONE_ELSE = "5c8a1f43-0000-4000-8000-000000000000"
WANT_Q1 = {"film_id": "Q1", "vote": "want"}


def poll(films: int = 1, slots: int = 2) -> dict:
    """A night with a poll: more than one film or more than one slot."""
    start = datetime.now(UTC) + timedelta(days=3)
    return {
        "films": [{"film_id": f"Q{900 + i}", "film": film(f"Q{900 + i}")} for i in range(films)],
        "slots": [
            (start + timedelta(days=i)).strftime("%Y-%m-%dT%H:%M:%S.000Z") for i in range(slots)
        ],
        "tz_offset_min": 330,
        "place": "PVR",
    }


async def test_create_join_and_the_roster(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await asha.ok("post", "/v1/groups", {"name": " Friday Crew "}, status=201)
    assert group["name"] == "Friday Crew" and CODE.match(group["invite_code"])
    assert (group["deck_version"], group["member_count"]) == (0, 1)
    code = group["invite_code"]
    assert (
        await world.http.get(f"/j/{code}")
    ).status_code == 200  # the landing page needs no login
    joined = await ravi.ok("post", "/v1/groups/join", {"code": code.lower()})
    assert joined["id"] == group["id"] and joined["member_count"] == 2
    assert await ravi.ok("post", "/v1/groups/join", {"code": f"{code[:4]} {code[4:]}"}) == joined
    detail = await ravi.ok("get", f"/v1/groups/{group['id']}")
    assert [(m["name"], m["owner"], m["me"], m["guest"]) for m in detail["members"]] == [
        ("Asha", True, False, False),
        ("Ravi", False, True, False),
    ]
    assert {m["handle"] for m in detail["members"]} == {"asha", "ravi"}
    for client in (asha, ravi):
        listed = await client.ok("get", "/v1/groups")
        assert [g["id"] for g in listed["items"]] == [group["id"]]
    joins = await world.rows("select args from messages where code = 'joined'")
    assert [r["args"] for r in joins] == [{"name": "Ravi"}]  # once, though Ravi joined twice


async def test_codes_and_who_may_change_a_group(world):
    asha, ravi, sam = [await world.user(n) for n in ("asha", "ravi", "sam")]
    group = await world.group(asha, "Crew", ravi)
    gid, old = group["id"], group["invite_code"]
    assert (await sam.get(f"/v1/groups/{gid}")).status_code == 404  # not a member
    for call in (
        ravi.patch(f"/v1/groups/{gid}", {"name": "Mine"}),
        ravi.delete(f"/v1/groups/{gid}"),
        ravi.post(f"/v1/groups/{gid}/invite/rotate"),
        ravi.post(f"/v1/groups/{gid}/guests", {"name": "Dad"}),
    ):
        assert (await call).status_code == 403
    assert (await sam.patch(f"/v1/groups/{gid}", {"name": "Mine"})).status_code == 404
    renamed = await asha.ok("patch", f"/v1/groups/{gid}", {"name": "Saturday Crew"})
    assert renamed["name"] == "Saturday Crew"
    fresh = await asha.ok("post", f"/v1/groups/{gid}/invite/rotate")
    assert CODE.match(fresh["invite_code"]) and fresh["invite_code"] != old
    stale = await sam.post("/v1/groups/join", {"code": old})
    assert stale.status_code == 404 and stale.json()["error"]["code"] == "invalid_code"
    nonsense = await sam.post("/v1/groups/join", {"code": "nonsense"})
    assert nonsense.json()["error"]["code"] == "invalid_code"
    assert (await sam.ok("post", "/v1/groups/join", {"code": fresh["invite_code"]}))["id"] == gid


async def test_join_limit_is_ten_an_hour(world):
    asha, sam = await world.user("asha"), await world.user("sam")
    group = await world.group(asha)
    for _ in range(10):
        await sam.post("/v1/groups/join", {"code": "AAAAAAAA"})
    limited = await sam.post("/v1/groups/join", {"code": group["invite_code"]})
    assert limited.status_code == 429
    world.clock.advance(3601)
    assert (await sam.post("/v1/groups/join", {"code": group["invite_code"]})).status_code == 200


async def test_a_group_holds_30_members_guests_included(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha)
    gid = group["id"]
    await world.pg.execute(
        "insert into group_members (group_id, guest_name) "
        "select $1::uuid, 'guest ' || i from generate_series(1, 28) i",
        UUID(gid),
    )
    assert (await asha.ok("get", f"/v1/groups/{gid}"))["member_count"] == 29
    last = await asha.ok("post", f"/v1/groups/{gid}/guests", {"name": "The thirtieth"}, status=201)
    assert last["guest"] is True
    full = await asha.post(f"/v1/groups/{gid}/guests", {"name": "One too many"})
    assert full.status_code == 409 and full.json()["error"]["code"] == "group_full"
    refused = await ravi.post("/v1/groups/join", {"code": group["invite_code"]})
    assert refused.status_code == 409 and refused.json()["error"]["code"] == "group_full"
    again = await asha.post("/v1/groups/join", {"code": group["invite_code"]})
    assert again.status_code == 200  # a member can always "join" again


async def test_a_user_is_in_at_most_20_groups(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    for i in range(20):
        await asha.ok("post", "/v1/groups", {"name": f"Group {i}"}, status=201)
    refused = await asha.post("/v1/groups", {"name": "One more"})
    assert refused.status_code == 409 and refused.json()["error"]["code"] == "group_limit"
    other = await world.group(ravi)
    joined = await asha.post("/v1/groups/join", {"code": other["invite_code"]})
    assert joined.status_code == 409 and joined.json()["error"]["code"] == "group_limit"


async def test_guests(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    dad = await asha.ok("post", f"/v1/groups/{gid}/guests", {"name": " Dad "}, status=201)
    flags = (dad["name"], dad["guest"], dad["handle"], dad["me"], dad["owner"])
    assert flags == ("Dad", True, None, False, False)
    dup = await asha.post(f"/v1/groups/{gid}/guests", {"name": "dAD"})
    assert dup.status_code == 409 and dup.json()["error"]["code"] == "name_taken"
    assert (await asha.post(f"/v1/groups/{gid}/guests", {"name": "   "})).status_code == 422
    members = (await ravi.ok("get", f"/v1/groups/{gid}"))["members"]
    assert [m["name"] for m in members] == ["Asha", "Ravi", "Dad"]
    assert members[2]["id"] == dad["id"] and members[2]["avatar_color"] == dad["avatar_color"]


async def test_only_the_owner_writes_for_a_guest(world):
    asha, ravi, meena = [await world.user(n) for n in ("asha", "ravi", "meena")]
    group = await world.group(asha, "Crew", ravi, meena)
    gid = group["id"]
    dad = await asha.ok("post", f"/v1/groups/{gid}/guests", {"name": "Dad"}, status=201)
    members = {m["name"]: m["id"] for m in (await asha.ok("get", f"/v1/groups/{gid}"))["members"]}
    # The owner writes for a guest.
    for_dad = {"swipes": [{**WANT_Q1, "member_id": dad["id"]}]}
    assert await asha.ok("put", f"/v1/groups/{gid}/swipes", for_dad) == {"saved": 1}
    mine_for_dad = await asha.ok("get", f"/v1/groups/{gid}/tallies", member_id=dad["id"])
    assert mine_for_dad["mine"] == {"Q1": "want"}
    assert (await asha.ok("get", f"/v1/groups/{gid}/tallies"))["mine"] == {}
    # Nobody else may, and the owner may not write for another account member.
    attempts = [
        (ravi, dad["id"]),
        (ravi, members["Asha"]),
        (asha, members["Ravi"]),
        (ravi, SOMEONE_ELSE),
    ]
    for actor, target in attempts:
        body = {"swipes": [{**WANT_Q1, "member_id": target}]}
        assert (await actor.put(f"/v1/groups/{gid}/swipes", body)).status_code == 403
        assert (await actor.get(f"/v1/groups/{gid}/tallies", member_id=target)).status_code == 403
    # Your own member id is fine, and so is leaving it out.
    own = {"swipes": [{**WANT_Q1, "member_id": members["Ravi"]}, {"film_id": "Q2", "vote": "skip"}]}
    assert await ravi.ok("put", f"/v1/groups/{gid}/swipes", own) == {"saved": 2}
    # The same rule holds for votes and RSVPs.
    night = await asha.ok("post", f"/v1/groups/{gid}/nights", poll(), status=201)
    option, nid = night["options"][0]["id"], night["id"]
    vote = {"option_ids": [option], "member_id": dad["id"]}
    assert (await ravi.put(f"/v1/nights/{nid}/votes", vote)).status_code == 403
    assert (await asha.ok("put", f"/v1/nights/{nid}/votes", vote))["approvals"][option] == 1
    assert (await ravi.get(f"/v1/nights/{nid}", member_id=dad["id"])).status_code == 403
    assert (await asha.ok("get", f"/v1/nights/{nid}", member_id=dad["id"]))["mine"] == [option]
    assert (await asha.ok("get", f"/v1/nights/{nid}"))["mine"] == []


async def test_swipes_and_tallies(world):
    asha, ravi, sam = [await world.user(n) for n in ("asha", "ravi", "sam")]
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    dad = await asha.ok("post", f"/v1/groups/{gid}/guests", {"name": "Dad"}, status=201)

    def put(client, *swipes):
        return client.ok("put", f"/v1/groups/{gid}/swipes", {"swipes": list(swipes)})

    await put(asha, WANT_Q1, {"film_id": "Q2", "vote": "seen"})
    await put(ravi, WANT_Q1)
    await put(asha, {"film_id": "Q1", "vote": "skip", "member_id": dad["id"]})
    result = await put(ravi, {"film_id": "Q3", "vote": "skip"}, {"film_id": "Q3", "vote": "want"})
    assert result == {"saved": 1}  # the last vote for a film wins
    tallies = await ravi.ok("get", f"/v1/groups/{gid}/tallies")
    assert tallies["tallies"] == {
        "Q1": {"want": 2, "skip": 1, "seen": 0},
        "Q2": {"want": 0, "skip": 0, "seen": 1},
        "Q3": {"want": 1, "skip": 0, "seen": 0},
    }
    assert tallies["mine"] == {"Q1": "want", "Q3": "want"}
    await put(ravi, {"film_id": "Q1", "vote": "skip"})  # a vote can change
    changed = await ravi.ok("get", f"/v1/groups/{gid}/tallies")
    assert changed["tallies"]["Q1"] == {"want": 1, "skip": 2, "seen": 0}
    too_many = {"swipes": [WANT_Q1] * 51}
    assert (await ravi.put(f"/v1/groups/{gid}/swipes", too_many)).status_code == 422
    custom = {"swipes": [{"film_id": "my:dev.1", "vote": "want"}]}
    assert (await ravi.put(f"/v1/groups/{gid}/swipes", custom)).status_code == 422
    assert (await sam.put(f"/v1/groups/{gid}/swipes", {"swipes": [WANT_Q1]})).status_code == 404


async def test_a_member_who_leaves_takes_their_swipes_and_votes(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    night = await asha.ok("post", f"/v1/groups/{gid}/nights", poll(), status=201)
    await ravi.ok("put", f"/v1/groups/{gid}/swipes", {"swipes": [WANT_Q1]})
    vote = {"option_ids": [night["options"][0]["id"]], "member_id": None}
    await ravi.ok("put", f"/v1/nights/{night['id']}/votes", vote)
    await ravi.ok("delete", f"/v1/groups/{gid}/members/me", status=204)
    assert (await ravi.get(f"/v1/groups/{gid}")).status_code == 404
    assert await world.value("select count(*) from swipes") == 0
    assert await world.value("select count(*) from night_votes") == 0
    assert (await asha.ok("get", f"/v1/groups/{gid}"))["member_count"] == 1
    left = await world.rows("select args from messages where code = 'left'")
    assert [r["args"] for r in left] == [{"name": "Ravi"}]


async def test_removing_members_and_handing_the_group_over(world):
    asha, ravi, meena = [await world.user(n) for n in ("asha", "ravi", "meena")]
    group = await world.group(asha, "Crew", ravi, meena)
    gid = group["id"]
    members = {m["name"]: m["id"] for m in (await asha.ok("get", f"/v1/groups/{gid}"))["members"]}
    assert (await ravi.delete(f"/v1/groups/{gid}/members/{members['Meena']}")).status_code == 403
    assert (await asha.delete(f"/v1/groups/{gid}/members/{SOMEONE_ELSE}")).status_code == 404
    assert (await asha.delete(f"/v1/groups/{gid}/members/not-an-id")).status_code == 404
    await asha.ok("delete", f"/v1/groups/{gid}/members/{members['Meena']}", status=204)  # removed
    assert (await meena.get(f"/v1/groups/{gid}")).status_code == 404
    await meena.ok("post", "/v1/groups/join", {"code": group["invite_code"]})  # back, after Ravi
    await asha.ok("post", f"/v1/groups/{gid}/guests", {"name": "Dad"}, status=201)
    # The owner leaves: Ravi joined first, so Ravi takes over. The guest stays.
    await asha.ok("delete", f"/v1/groups/{gid}/members/me", status=204)
    detail = await ravi.ok("get", f"/v1/groups/{gid}")
    roster = [(m["name"], m["owner"]) for m in detail["members"]]
    assert roster == [("Ravi", True), ("Meena", False), ("Dad", False)]
    renamed = await ravi.ok("patch", f"/v1/groups/{gid}", {"name": "Ravi's crew"})
    assert renamed["name"] == "Ravi's crew"
    # Ravi leaves and Meena takes over. Meena leaves: only a guest is left, so the group goes.
    await ravi.ok("delete", f"/v1/groups/{gid}/members/me", status=204)
    assert (await meena.ok("get", f"/v1/groups/{gid}"))["members"][0]["owner"] is True
    await meena.ok("delete", f"/v1/groups/{gid}/members/me", status=204)
    assert await world.value("select count(*) from groups") == 0
    assert await world.value("select count(*) from group_members") == 0


async def test_the_owner_can_delete_the_group(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    await asha.ok("post", f"/v1/groups/{gid}/nights", poll(), status=201)
    await ravi.ok("post", f"/v1/groups/{gid}/messages", {"body": "hi"}, status=201)
    await asha.ok("delete", f"/v1/groups/{gid}", status=204)
    assert (await ravi.get(f"/v1/groups/{gid}")).status_code == 404
    for table in ("groups", "group_members", "group_decks", "nights", "messages", "swipes"):
        assert await world.value(f"select count(*) from {table}") == 0, table


async def test_the_shared_list(world):
    asha, ravi, sam = [await world.user(n) for n in ("asha", "ravi", "sam")]
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    await asha.ok("put", f"/v1/groups/{gid}/films/Q949228", {"film": film()}, status=204)
    renamed = {"film": film(title="Kantara 2")}
    await ravi.ok("put", f"/v1/groups/{gid}/films/Q949228", renamed, status=204)
    listed = await ravi.ok("get", f"/v1/groups/{gid}/films")
    assert [(i["film_id"], i["film"]["t"]) for i in listed["items"]] == [("Q949228", "Kantara 2")]
    await ravi.ok("put", f"/v1/groups/{gid}/films/Q2", {"film": film("Q2")}, status=204)
    both = await asha.ok("get", f"/v1/groups/{gid}/films")
    assert [i["film_id"] for i in both["items"]] == ["Q949228", "Q2"]
    bad = [
        ("my:dev.1", {"film": {"id": "my:dev.1", "t": "Mine"}}),  # custom films are not shared
        ("Q3", {"film": film("Q4")}),  # the snapshot of another film
        ("Q3", {"film": {"id": "Q3"}}),  # no title
        ("Q3", {"film": {**film("Q3"), "p": "file:posters/1.jpg"}}),
    ]
    for film_id, body in bad:
        assert (await ravi.put(f"/v1/groups/{gid}/films/{film_id}", body)).status_code == 422, (
            film_id
        )
    assert (await sam.put(f"/v1/groups/{gid}/films/Q3", {"film": film("Q3")})).status_code == 404
    await ravi.ok("delete", f"/v1/groups/{gid}/films/Q949228", status=204)
    left = await asha.ok("get", f"/v1/groups/{gid}/films")
    assert [i["film_id"] for i in left["items"]] == ["Q2"]


async def test_the_shared_list_holds_200_films(world):
    asha = await world.user("asha")
    group = await world.group(asha)
    gid = group["id"]
    await world.pg.execute(
        "insert into group_films (group_id, film_id, film) "
        'select $1::uuid, \'Q\' || (1000 + i), \'{"id": "Q1", "t": "x"}\'::jsonb '
        "from generate_series(1, 200) i",
        UUID(gid),
    )
    full = await asha.put(f"/v1/groups/{gid}/films/Q5", {"film": film("Q5")})
    assert full.status_code == 409 and full.json()["error"]["code"] == "list_full"
    again = await asha.put(f"/v1/groups/{gid}/films/Q1001", {"film": film("Q1001")})
    assert again.status_code == 204  # a film already on the list is not a new one


async def test_deck_versions_conflicts_and_the_write_limit(world):
    asha, ravi, sam = [await world.user(n) for n in ("asha", "ravi", "sam")]
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    other = await world.group(asha, "Other")
    assert await ravi.ok("get", f"/v1/groups/{gid}/deck") == {"version": 0, "items": []}
    deck = [{"film_id": "Q10", "film": film("Q10")}, {"film_id": "Q11", "film": film("Q11")}]

    def put(client, base, items, group_id=gid):
        return client.put(f"/v1/groups/{group_id}/deck", {"base_version": base, "items": items})

    first = await put(asha, 0, deck)
    assert (first.status_code, first.json()) == (200, {"version": 1})
    # One write per 10 seconds per member per group, so one member cannot starve
    # the rest. Ravi still has his own budget right after Asha's write.
    soon = await put(ravi, 1, deck)
    assert (soon.status_code, soon.json()) == (200, {"version": 2})
    assert (await put(ravi, 2, deck)).status_code == 429
    assert (await put(asha, 1, deck)).status_code == 429  # Asha's own window is still full
    assert (await put(asha, 2, deck, other["id"])).status_code == 200
    world.clock.advance(11)
    stale = await put(ravi, 0, deck[:1])
    assert stale.status_code == 409
    assert stale.json()["error"] == {
        "code": "deck_conflict",
        "message": "The deck changed",
        "detail": {"current_version": 2},
    }
    fetched = await ravi.ok("get", f"/v1/groups/{gid}/deck")
    assert (fetched["version"], [i["film_id"] for i in fetched["items"]]) == (2, ["Q10", "Q11"])
    assert all(i["seen_by"] == 0 for i in fetched["items"])
    world.clock.advance(11)
    second = await put(ravi, 2, deck[:1])
    assert (second.status_code, second.json()) == (200, {"version": 3})
    assert (await asha.ok("get", f"/v1/groups/{gid}"))["deck_version"] == 3
    world.clock.advance(11)
    wrong_film = [{**deck[0], "film": film("Q99")}]
    custom = [{"film_id": "my:dev.1", "film": film("Q1")}]
    many = [{"film_id": f"Q{i}", "film": film(f"Q{i}")} for i in range(121)]
    for items in (deck + deck[:1], custom, wrong_film, many):
        assert (await put(asha, 2, items)).status_code == 422
    assert (await put(sam, 2, deck)).status_code == 404
    assert (await sam.get(f"/v1/groups/{gid}/deck")).status_code == 404


async def test_the_seen_rule(world):
    olive = await world.user("olive", visibility="friends")
    fred = await world.user("fred")  # private to start with
    group = await world.group(olive, "Crew", fred)
    gid = group["id"]
    await world.friends(olive, fred)
    dad = await olive.ok("post", f"/v1/groups/{gid}/guests", {"name": "Dad"}, status=201)
    await olive.push(
        stub("o10", "Q10", date=today()), stub("o11", "Q11", date=today(), private=True)
    )
    await fred.push(stub("f12", "Q12", date=today()), stub("f10", "Q10", date=today()))
    swiped = {"swipes": [{"film_id": "Q13", "vote": "seen", "member_id": dad["id"]}]}
    await olive.ok("put", f"/v1/groups/{gid}/swipes", swiped)
    deck = [{"film_id": f"Q{i}", "film": film(f"Q{i}")} for i in (10, 11, 12, 13)]
    await olive.ok("put", f"/v1/groups/{gid}/deck", {"base_version": 0, "items": deck})

    async def seen_by(client):
        items = (await client.ok("get", f"/v1/groups/{gid}/deck"))["items"]
        return {i["film_id"]: i["seen_by"] for i in items}

    # Fred's profile is private: Olive counts her own films and the guest's swipe.
    assert await seen_by(olive) == {"Q10": 1, "Q11": 1, "Q12": 0, "Q13": 1}
    # Fred counts his own films, Olive's public ones, and the swipe. Not Olive's private Q11.
    assert await seen_by(fred) == {"Q10": 2, "Q11": 0, "Q12": 1, "Q13": 1}
    # Fred opens his profile to friends: now Olive can count his public films too.
    await fred.ok("patch", "/v1/me", {"visibility": "friends"})
    assert await seen_by(olive) == {"Q10": 2, "Q11": 1, "Q12": 1, "Q13": 1}
    inputs = await fred.ok("get", f"/v1/groups/{gid}/deck-inputs")
    assert set(inputs["seen"]) == {"Q10", "Q12", "Q13"}


async def test_deck_inputs_name_no_member(world):
    olive = await world.user("olive", visibility="friends")
    fred = await world.user("fred")
    sam = await world.user("sam")
    group = await world.group(olive, "Crew", fred)
    gid = group["id"]
    taste = {
        "kind": "taste",
        "id": "taste",
        "updated_at": stub("x")["updated_at"],
        "deleted": False,
    }
    await olive.push({**taste, "film": None, "data": {"v": 1, "traits": {"g:drama": 80}}})
    await fred.push({**taste, "film": None, "data": {"v": 1, "traits": {"g:comedy": 70}}})
    await olive.push(wish("Q20"))
    await fred.push(wish("Q20"), wish("Q21"))
    await olive.ok("put", f"/v1/groups/{gid}/films/Q21", {"film": film("Q21")}, status=204)
    await olive.ok("put", f"/v1/groups/{gid}/films/Q22", {"film": film("Q22")}, status=204)
    inputs = await fred.ok("get", f"/v1/groups/{gid}/deck-inputs")
    assert sorted(next(iter(t["traits"])) for t in inputs["tastes"]) == ["g:comedy", "g:drama"]
    wanted = [(w["film_id"], w["n"]) for w in inputs["wanted"]]
    assert wanted == [("Q20", 2), ("Q21", 2), ("Q22", 1)]
    assert all(w["film"]["id"] == w["film_id"] for w in inputs["wanted"])
    text = json.dumps(inputs)
    assert str(olive.id) not in text and str(fred.id) not in text
    assert "olive" not in text and "fred" not in text
    assert (await sam.get(f"/v1/groups/{gid}/deck-inputs")).status_code == 404


async def test_the_roster_hides_a_blocked_member_both_ways(world):
    olive, fred, meena = [await world.user(n) for n in ("olive", "fred", "meena")]
    group = await world.group(olive, "Crew", fred, meena)
    gid = group["id"]
    await olive.ok("post", "/v1/blocks", {"user_id": str(fred.id)}, status=204)

    async def roster(client):
        detail = await client.ok("get", f"/v1/groups/{gid}")
        return [m["name"] for m in detail["members"]], detail["member_count"]

    assert await roster(olive) == (["Olive", "Meena"], 3)
    assert await roster(fred) == (["Fred", "Meena"], 3)
    assert await roster(meena) == (["Olive", "Fred", "Meena"], 3)
