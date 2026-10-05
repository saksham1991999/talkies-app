"""Movie nights: polls, closing, RSVPs, and the wrap-up."""

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID

from tests.db.conftest import film


def at(delta: timedelta) -> str:
    return (datetime.now(UTC) + delta).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def night_body(films=2, slots=2, start=timedelta(days=3), place="PVR", tz=330) -> dict:
    return {
        "films": [{"film_id": f"Q{900 + i}", "film": film(f"Q{900 + i}")} for i in range(films)],
        "slots": [at(start + timedelta(days=i)) for i in range(slots)],
        "tz_offset_min": tz,
        "place": place,
    }


async def crew(world):
    asha, ravi, meena = [await world.user(n) for n in ("asha", "ravi", "meena")]
    group = await world.group(asha, "Crew", ravi, meena)
    members = {
        m["name"]: m["id"] for m in (await asha.ok("get", f"/v1/groups/{group['id']}"))["members"]
    }
    return asha, ravi, meena, group["id"], members


def option(night: dict, kind: str, position: int) -> dict:
    return next(o for o in night["options"] if o["kind"] == kind and o["position"] == position)


async def test_a_poll_from_creation_to_close(world):
    asha, ravi, meena, gid, _ = await crew(world)
    body = night_body()
    night = await ravi.ok(
        "post", f"/v1/groups/{gid}/nights", body, status=201
    )  # any member may propose
    nid = night["id"]
    assert (night["status"], night["host_id"], night["event"], night["rsvps"]) == (
        "poll",
        str(ravi.id),
        None,
        [],
    )
    assert [(o["kind"], o["position"], o["approvals"]) for o in night["options"]] == [
        ("film", 0, 0),
        ("film", 1, 0),
        ("slot", 0, 0),
        ("slot", 1, 0),
    ]
    film_a, film_b = option(night, "film", 0), option(night, "film", 1)
    slot_1, slot_2 = option(night, "slot", 0), option(night, "slot", 1)
    assert (film_a["film_id"], film_a["film"]["id"], film_a["starts_at"]) == ("Q900", "Q900", None)
    assert slot_1["film"] is None and slot_1["starts_at"] == body["slots"][0]
    assert (night["tz_offset_min"], night["place"]) == (330, "PVR")

    def vote(client, *options):
        return client.ok(
            "put",
            f"/v1/nights/{nid}/votes",
            {"option_ids": [o["id"] for o in options], "member_id": None},
        )

    await vote(asha, film_a)
    first = await vote(ravi, film_a, slot_1)
    assert first["approvals"] == {
        film_a["id"]: 2,
        film_b["id"]: 0,
        slot_1["id"]: 1,
        slot_2["id"]: 0,
    }
    await vote(ravi, film_b, slot_2)  # replaces the earlier approvals
    await vote(meena, film_b, slot_1, slot_2)
    seen = await meena.ok("get", f"/v1/nights/{nid}")
    assert sorted(seen["mine"]) == sorted([film_b["id"], slot_1["id"], slot_2["id"]])
    assert {o["id"]: o["approvals"] for o in seen["options"]} == {
        film_a["id"]: 1,
        film_b["id"]: 2,
        slot_1["id"]: 1,
        slot_2["id"]: 2,
    }
    other_night = await asha.ok(
        "post", f"/v1/groups/{gid}/nights", night_body(films=1, slots=2), status=201
    )
    foreign = {"option_ids": [other_night["options"][0]["id"]], "member_id": None}
    assert (await ravi.put(f"/v1/nights/{nid}/votes", foreign)).status_code == 422
    assert (
        await meena.post(f"/v1/nights/{nid}/close", {})
    ).status_code == 403  # not the host or owner
    closed = await asha.ok(
        "post",
        f"/v1/nights/{nid}/close",
        {"film_option_id": None, "slot_option_id": None, "place": "Inox"},
    )
    assert closed["status"] == "set"
    assert closed["event"] == {
        "film_id": "Q901",
        "film": film_b["film"],
        "starts_at": slot_2["starts_at"],
        "tz_offset_min": 330,
        "place": "Inox",
    }
    again = await asha.post(f"/v1/nights/{nid}/close", {})
    assert again.status_code == 409 and again.json()["error"]["code"] == "not_polling"
    late = await ravi.put(f"/v1/nights/{nid}/votes", {"option_ids": [], "member_id": None})
    assert late.status_code == 409 and late.json()["error"]["code"] == "not_polling"
    sets = await world.rows("select args, night_id from messages where code = 'night_set'")
    assert [(r["args"], str(r["night_id"])) for r in sets] == [
        ({"night_id": nid, "film_id": "Q901", "starts_at": slot_2["starts_at"]}, nid)
    ]
    opens = await world.rows("select args from messages where code = 'poll_open'")
    assert nid in [r["args"]["night_id"] for r in opens]


async def test_a_tie_goes_to_the_lowest_position_and_the_host_may_pick(world):
    asha, ravi, _, gid, _ = await crew(world)
    night = await asha.ok(
        "post", f"/v1/groups/{gid}/nights", night_body(films=3, slots=2), status=201
    )
    nid = night["id"]
    films = [option(night, "film", i) for i in range(3)]
    slots = [option(night, "slot", i) for i in range(2)]
    await ravi.ok(
        "put",
        f"/v1/nights/{nid}/votes",
        {"option_ids": [films[2]["id"], slots[1]["id"]], "member_id": None},
    )
    await asha.ok(
        "put",
        f"/v1/nights/{nid}/votes",
        {"option_ids": [films[1]["id"], slots[0]["id"]], "member_id": None},
    )
    # One approval each: the lower position wins both.
    closed = await asha.ok(
        "post",
        f"/v1/nights/{nid}/close",
        {"film_option_id": None, "slot_option_id": None, "place": None},
    )
    assert (
        closed["event"]["film_id"] == "Q901"
        and closed["event"]["starts_at"] == slots[0]["starts_at"]
    )
    assert closed["event"]["place"] == "PVR"  # no new place: the night's own stays
    second = await asha.ok(
        "post", f"/v1/groups/{gid}/nights", night_body(films=3, slots=2), status=201
    )
    picks = {
        "film_option_id": option(second, "film", 2)["id"],
        "slot_option_id": option(second, "slot", 1)["id"],
        "place": None,
    }
    wrong_kind = {**picks, "film_option_id": option(second, "slot", 0)["id"]}
    assert (await asha.post(f"/v1/nights/{second['id']}/close", wrong_kind)).status_code == 422
    picked = await asha.ok("post", f"/v1/nights/{second['id']}/close", picks)
    assert picked["event"]["film_id"] == "Q902"


async def test_one_film_and_one_slot_make_a_night_that_is_set_at_once(world):
    asha, ravi, _, gid, _ = await crew(world)
    body = night_body(films=1, slots=1, place=None)
    night = await ravi.ok("post", f"/v1/groups/{gid}/nights", body, status=201)
    assert night["status"] == "set" and night["place"] is None
    assert night["event"] == {
        "film_id": "Q900",
        "film": film("Q900"),
        "starts_at": body["slots"][0],
        "tz_offset_min": 330,
        "place": None,
    }
    vote = await ravi.put(f"/v1/nights/{night['id']}/votes", {"option_ids": [], "member_id": None})
    assert vote.status_code == 409
    messages = await world.rows(
        "select code from messages where code like 'night_%' or code = 'poll_open'"
    )
    assert [r["code"] for r in messages] == ["night_set"]


async def test_creation_rules(world):
    asha, _, _, gid, _ = await crew(world)
    sam = await world.user("sam")
    bad = {
        "slot_too_early": night_body(slots=1, start=timedelta(days=-2)),
        "slot_too_late": night_body(slots=1, start=timedelta(days=401)),
        "same_film_twice": {**night_body(films=2), "films": [night_body()["films"][0]] * 2},
        "same_slot_twice": {**night_body(), "slots": [at(timedelta(days=3))] * 2},
        "four_films": night_body(films=4),
        "three_slots": night_body(slots=3),
        "no_films": night_body(films=0),
        "custom_film": {**night_body(), "films": [{"film_id": "my:dev.1", "film": film("Q1")}]},
        "other_film": {**night_body(), "films": [{"film_id": "Q1", "film": film("Q2")}]},
        "far_zone": night_body(tz=900),
    }
    for name, body in bad.items():
        reply = await asha.post(f"/v1/groups/{gid}/nights", body)
        assert reply.status_code == 422, name
    just_in = night_body(slots=1, start=timedelta(hours=-20))
    assert (await asha.post(f"/v1/groups/{gid}/nights", just_in)).status_code == 201
    assert (await sam.post(f"/v1/groups/{gid}/nights", night_body())).status_code == 404
    assert (await sam.get(f"/v1/groups/{gid}/nights")).status_code == 404


async def test_rsvp_needs_a_set_night_and_lists_only_those_who_replied(world):
    asha, ravi, meena, gid, members = await crew(world)
    dad = await asha.ok("post", f"/v1/groups/{gid}/guests", {"name": "Dad"}, status=201)
    poll = await asha.ok("post", f"/v1/groups/{gid}/nights", night_body(), status=201)
    reply = await ravi.put(f"/v1/nights/{poll['id']}/rsvp", {"response": "yes", "member_id": None})
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "not_set"
    night = await asha.ok(
        "post", f"/v1/groups/{gid}/nights", night_body(films=1, slots=1), status=201
    )
    nid = night["id"]
    await ravi.ok(
        "put", f"/v1/nights/{nid}/rsvp", {"response": "yes", "member_id": None}, status=204
    )
    await meena.ok(
        "put", f"/v1/nights/{nid}/rsvp", {"response": "maybe", "member_id": None}, status=204
    )
    await asha.ok(
        "put", f"/v1/nights/{nid}/rsvp", {"response": "no", "member_id": dad["id"]}, status=204
    )
    forbidden = await ravi.put(
        f"/v1/nights/{nid}/rsvp", {"response": "yes", "member_id": dad["id"]}
    )
    assert forbidden.status_code == 403
    await meena.ok(
        "put", f"/v1/nights/{nid}/rsvp", {"response": "yes", "member_id": None}, status=204
    )
    shown = await asha.ok("get", f"/v1/nights/{nid}")
    replies = {r["member_id"]: r["response"] for r in shown["rsvps"]}
    assert replies == {members["Ravi"]: "yes", members["Meena"]: "yes", dad["id"]: "no"}
    assert members["Asha"] not in replies  # Asha has not replied
    sam = await world.user("sam")
    assert (
        await sam.put(f"/v1/nights/{nid}/rsvp", {"response": "yes", "member_id": None})
    ).status_code == 404
    assert (await sam.get(f"/v1/nights/{nid}")).status_code == 404


async def test_listing_and_deleting_nights(world):
    asha, ravi, meena, gid, _ = await crew(world)
    first = await ravi.ok(
        "post", f"/v1/groups/{gid}/nights", night_body(films=1, slots=1), status=201
    )
    second = await asha.ok("post", f"/v1/groups/{gid}/nights", night_body(), status=201)
    listed = await meena.ok("get", f"/v1/groups/{gid}/nights")
    assert [n["id"] for n in listed["items"]] == [second["id"], first["id"]]  # newest first
    assert (
        await meena.delete(f"/v1/nights/{first['id']}")
    ).status_code == 403  # neither host nor owner
    await ravi.ok("delete", f"/v1/nights/{first['id']}", status=204)  # the host
    await asha.ok("delete", f"/v1/nights/{second['id']}", status=204)  # the owner
    assert (await meena.ok("get", f"/v1/groups/{gid}/nights"))["items"] == []
    assert (await meena.get(f"/v1/nights/{second['id']}")).status_code == 404
    assert await world.value("select count(*) from night_options") == 0


async def wrapped_night(world):
    """A night an hour from now, with Asha, Ravi, and the guest Dad going and Meena not."""
    asha, ravi, meena, gid, members = await crew(world)
    dad = await asha.ok("post", f"/v1/groups/{gid}/guests", {"name": "Dad"}, status=201)
    body = night_body(films=1, slots=1, start=timedelta(hours=1))
    night = await asha.ok("post", f"/v1/groups/{gid}/nights", body, status=201)
    nid = night["id"]
    for client, answer, member in ((asha, "yes", None), (ravi, "yes", None), (meena, "no", None)):
        await client.ok(
            "put", f"/v1/nights/{nid}/rsvp", {"response": answer, "member_id": member}, status=204
        )
    await asha.ok(
        "put", f"/v1/nights/{nid}/rsvp", {"response": "yes", "member_id": dad["id"]}, status=204
    )
    return asha, ravi, meena, gid, nid, members, dad, body


def stubs_of(records: dict, nid: str) -> list[dict]:
    return [r for r in records["records"] if r["id"] == f"night-{nid}"]


async def test_wrapup_writes_one_stub_per_account_member_who_went(world):
    asha, ravi, meena, gid, nid, members, dad, body = await wrapped_night(world)
    forbidden = await ravi.post(
        f"/v1/nights/{nid}/wrapup", {"seat_row": "F", "first_seat": 7, "member_ids": None}
    )
    assert forbidden.status_code == 403
    result = await asha.ok(
        "post", f"/v1/nights/{nid}/wrapup", {"seat_row": "F", "first_seat": 7, "member_ids": None}
    )
    assert result == {"created": 2, "skipped": 0}
    local = (
        datetime.fromisoformat(body["slots"][0].replace("Z", "+00:00")) + timedelta(minutes=330)
    ).date()
    for client, seat, company in ((asha, "F7", "Ravi, Dad"), (ravi, "F8", "Asha, Dad")):
        (record,) = stubs_of(await client.pull(), nid)
        data = record["data"]
        assert (data["id"], data["no"], data["film"], data["prec"]) == (
            f"night-{nid}",
            0,
            "Q900",
            "day",
        )
        assert (data["date"], data["place"], data["seat"], data["with"]) == (
            local.isoformat(),
            "PVR",
            seat,
            company,
        )
        assert data["created"].endswith("Z") and "rating" not in data and "priv" not in data
        assert record["film"] == film("Q900") and record["deleted"] is False and record["seq"] > 0
    assert stubs_of(await meena.pull(), nid) == []  # Meena said no
    assert await world.value("select count(*) from stubs where id = $1", f"night-{nid}") == 2
    assert (
        await world.value(
            "select count(*) from stubs where id = $1 and feed_seq is not null", f"night-{nid}"
        )
        == 2
    )
    night = await asha.ok("get", f"/v1/nights/{nid}")
    assert night["status"] == "done"
    wrapped = await world.rows("select args from messages where code = 'wrapped'")
    assert [r["args"] for r in wrapped] == [{"night_id": nid}]


async def test_wrapup_twice_adds_nothing_and_a_deleted_stub_stays_deleted(world):
    asha, ravi, _, _, nid, _, _, _ = await wrapped_night(world)
    first = {"seat_row": "B", "first_seat": 1, "member_ids": None}
    assert await asha.ok("post", f"/v1/nights/{nid}/wrapup", first) == {"created": 2, "skipped": 0}
    assert await asha.ok("post", f"/v1/nights/{nid}/wrapup", first) == {"created": 0, "skipped": 2}
    assert await world.value("select count(*) from stubs where id = $1", f"night-{nid}") == 2
    assert await world.value("select count(*) from messages where code = 'wrapped'") == 1
    (record,) = stubs_of(await ravi.pull(), nid)
    tombstone = {
        "kind": "stub",
        "id": f"night-{nid}",
        "updated_at": (datetime.now(UTC) + timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "deleted": True,
        "film": None,
        "data": {},
    }
    assert record["seq"] and (await ravi.push(tombstone))["conflicts"] == []
    assert await asha.ok("post", f"/v1/nights/{nid}/wrapup", first) == {"created": 0, "skipped": 2}
    (record,) = stubs_of(await ravi.pull(), nid)
    assert record["deleted"] is True  # the wrap-up did not bring it back


async def test_two_wrapups_at_once_still_make_one_stub_each(world):
    asha, _, _, _, nid, _, _, _ = await wrapped_night(world)
    body = {"seat_row": None, "first_seat": None, "member_ids": None}
    results = await asyncio.gather(
        *[asha.ok("post", f"/v1/nights/{nid}/wrapup", body) for _ in range(4)]
    )
    assert sum(r["created"] for r in results) == 2
    assert await world.value("select count(*) from stubs where id = $1", f"night-{nid}") == 2
    assert await world.value("select count(*) from messages where code = 'wrapped'") == 1


async def test_wrapup_with_named_members_and_a_random_seat(world):
    asha, ravi, meena, gid, nid, members, dad, _ = await wrapped_night(world)
    named = {"seat_row": None, "first_seat": None, "member_ids": [members["Meena"], dad["id"]]}
    result = await asha.ok("post", f"/v1/nights/{nid}/wrapup", named)
    assert result == {"created": 1, "skipped": 0}  # the guest gets no stub
    (record,) = stubs_of(await meena.pull(), nid)
    seat = record["data"]["seat"]
    assert "A" <= seat[0] <= "Z" and 1 <= int(seat[1:]) <= 20
    assert record["data"]["with"] == "Dad"
    assert stubs_of(await ravi.pull(), nid) == []


async def test_wrapup_needs_a_set_night(world):
    asha, _, _, gid, _ = await crew(world)
    poll = await asha.ok("post", f"/v1/groups/{gid}/nights", night_body(), status=201)
    body = {"seat_row": None, "first_seat": None, "member_ids": None}
    reply = await asha.post(f"/v1/nights/{poll['id']}/wrapup", body)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "not_set"
    stranger = await world.user("sam")
    assert (await stranger.post(f"/v1/nights/{poll['id']}/wrapup", body)).status_code == 404
    bad = {"seat_row": "AB", "first_seat": 100, "member_ids": None}
    assert (await asha.post(f"/v1/nights/{poll['id']}/wrapup", bad)).status_code == 422


async def test_a_deleted_host_leaves_the_night_without_a_host(world):
    asha, ravi, _, gid, _ = await crew(world)
    night = await ravi.ok("post", f"/v1/groups/{gid}/nights", night_body(), status=201)
    await ravi.ok("delete", "/v1/me", status=204)
    shown = await asha.ok("get", f"/v1/nights/{night['id']}")
    assert shown["host_id"] is None
    assert UUID(shown["group_id"]) == UUID(gid)
