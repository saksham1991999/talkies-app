"""Friend requests, lookup, blocks, sent films, feed pages, reports."""

import asyncio
from datetime import UTC, datetime, timedelta

from tests.db.conftest import film, stub, today


async def test_a_request_and_its_answer(world):
    asha = await world.user("asha")
    ravi = await world.user("ravi")
    sent = await asha.ok("post", "/v1/friends/requests", {"user_id": str(ravi.id)})
    assert sent == {"status": "pending"}
    duplicate = await asha.post("/v1/friends/requests", {"user_id": str(ravi.id)})
    assert duplicate.status_code == 409 and duplicate.json()["error"]["code"] == "already_pending"
    outgoing = await asha.ok("get", "/v1/friends/requests")
    assert [c["handle"] for c in outgoing["outgoing"]] == ["ravi"] and outgoing["incoming"] == []
    incoming = await ravi.ok("get", "/v1/friends/requests")
    assert [c["handle"] for c in incoming["incoming"]] == ["asha"] and incoming["outgoing"] == []
    lookup = await ravi.ok("get", "/v1/users/lookup", handle="asha")
    assert lookup["relation"] == "incoming"
    assert (await asha.ok("get", "/v1/users/lookup", handle="ravi"))["relation"] == "outgoing"
    await ravi.ok("post", f"/v1/friends/requests/{asha.id}/accept", status=204)
    assert (await asha.ok("get", "/v1/users/lookup", handle="ravi"))["relation"] == "friend"
    for client, other in ((asha, "ravi"), (ravi, "asha")):
        assert [i["card"]["handle"] for i in (await client.ok("get", "/v1/friends"))["items"]] == [
            other
        ]
        assert (await client.ok("get", "/v1/friends/requests")) == {"incoming": [], "outgoing": []}
    again = await asha.ok("post", "/v1/friends/requests", {"user_id": str(ravi.id)})
    assert again == {"status": "friends"}  # already friends: no new request


async def test_two_requests_that_cross_make_friends(world):
    asha = await world.user("asha")
    ravi = await world.user("ravi")
    await asha.ok("post", "/v1/friends/requests", {"user_id": str(ravi.id)})
    mutual = await ravi.ok("post", "/v1/friends/requests", {"user_id": str(asha.id)})
    assert mutual == {"status": "friends"}
    assert await world.value("select count(*) from friendships") == 2
    assert await world.value("select count(*) from friend_requests") == 0


async def test_requests_at_the_same_moment_never_leave_two_pending_rows(world):
    asha = await world.user("asha")
    ravi = await world.user("ravi")
    first, second = await asyncio.gather(
        asha.post("/v1/friends/requests", {"user_id": str(ravi.id)}),
        ravi.post("/v1/friends/requests", {"user_id": str(asha.id)}),
    )
    assert {first.status_code, second.status_code} == {200}
    pending = await world.value("select count(*) from friend_requests")
    friends = await world.value("select count(*) from friendships")
    assert (pending, friends) in {(1, 0), (0, 2)}  # one pending request, or already friends


async def test_decline_cancel_and_unfriend(world):
    asha, ravi, meena = [await world.user(n) for n in ("asha", "ravi", "meena")]
    await asha.ok("post", "/v1/friends/requests", {"user_id": str(ravi.id)})
    await ravi.ok("delete", f"/v1/friends/requests/{asha.id}", status=204)  # decline
    assert (await ravi.delete(f"/v1/friends/requests/{asha.id}")).status_code == 404
    await asha.ok("post", "/v1/friends/requests", {"user_id": str(meena.id)})
    await asha.ok("delete", f"/v1/friends/requests/{meena.id}", status=204)  # cancel
    assert (await meena.post(f"/v1/friends/requests/{asha.id}/accept")).status_code == 404
    await world.friends(asha, ravi)
    await asha.ok("delete", f"/v1/friends/{ravi.id}", status=204)
    assert (await asha.ok("get", "/v1/friends"))["items"] == []
    assert (await ravi.ok("get", "/v1/friends"))["items"] == []


async def test_request_edge_cases(world):
    asha = await world.user("asha")
    assert (await asha.post("/v1/friends/requests", {"user_id": str(asha.id)})).status_code == 422
    stranger = {"user_id": "5c8a1f43-0000-4000-8000-000000000000"}
    assert (await asha.post("/v1/friends/requests", stranger)).status_code == 404


async def test_lookup_rules_and_limit(world):
    asha = await world.user("asha")
    await world.user("ravi")
    for handle in ("@RAVI", " ravi ", "ravi"):
        assert (await asha.ok("get", "/v1/users/lookup", handle=handle))["card"]["handle"] == "ravi"
    for handle in ("nobody", "asha", "r!", "x" * 40):  # unknown, myself, malformed
        assert (await asha.get("/v1/users/lookup", handle=handle)).status_code == 404
    for _ in range(30 - 7):
        await asha.get("/v1/users/lookup", handle="ravi")
    limited = await asha.get("/v1/users/lookup", handle="ravi")
    assert limited.status_code == 429 and int(limited.headers["retry-after"]) > 0
    world.clock.advance(3601)
    assert (await asha.get("/v1/users/lookup", handle="ravi")).status_code == 200


async def test_block_removes_the_friendship_and_requests(world):
    asha, ravi, meena = [await world.user(n) for n in ("asha", "ravi", "meena")]
    await world.friends(asha, ravi)
    await meena.ok("post", "/v1/friends/requests", {"user_id": str(asha.id)})
    await asha.ok("post", "/v1/blocks", {"user_id": str(ravi.id)}, status=204)
    await asha.ok("post", "/v1/blocks", {"user_id": str(meena.id)}, status=204)
    assert await world.value("select count(*) from friendships") == 0
    assert await world.value("select count(*) from friend_requests") == 0
    assert [c["handle"] for c in (await asha.ok("get", "/v1/blocks"))["items"]] == ["meena", "ravi"]
    assert (await asha.post("/v1/blocks", {"user_id": str(asha.id)})).status_code == 422
    assert (
        await asha.post("/v1/blocks", {"user_id": "5c8a1f43-0000-4000-8000-000000000000"})
    ).status_code == 404
    await asha.ok("delete", f"/v1/blocks/{ravi.id}", status=204)
    assert [c["handle"] for c in (await asha.ok("get", "/v1/blocks"))["items"]] == ["meena"]
    assert (await asha.ok("get", "/v1/friends"))["items"] == []  # unblocking does not restore it
    await asha.ok("delete", f"/v1/blocks/{ravi.id}", status=204)  # twice is fine


async def test_send_a_film(world):
    asha, ravi, sam = [await world.user(n) for n in ("asha", "ravi", "sam")]
    await world.friends(asha, ravi)
    body = {
        "user_id": str(ravi.id),
        "film_id": "Q949228",
        "film": film(),
        "note": "You will love this",
    }
    assert (await asha.ok("post", "/v1/films/send", body, status=201)) == {}
    feed = await ravi.ok("get", "/v1/feed")
    assert [(i["kind"], i["film_id"], i["note"], i["user"]["handle"]) for i in feed["items"]] == [
        ("sent", "Q949228", "You will love this", "asha")
    ]
    assert feed["items"][0]["id"].startswith("s:")
    assert (await asha.post("/v1/films/send", {**body, "user_id": str(sam.id)})).status_code == 404
    assert (await asha.post("/v1/films/send", {**body, "user_id": str(asha.id)})).status_code == 422
    assert (await asha.post("/v1/films/send", {**body, "film_id": "my:dev.1"})).status_code == 422
    assert (
        await asha.post("/v1/films/send", {**body, "film_id": "Q1"})
    ).status_code == 422  # film is Q949228
    await ravi.ok("post", "/v1/blocks", {"user_id": str(asha.id)}, status=204)
    assert (await asha.post("/v1/films/send", body)).status_code == 404
    assert (await ravi.ok("get", "/v1/feed"))["items"] == []


async def test_send_film_limit(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    await world.friends(asha, ravi)
    body = {"user_id": str(ravi.id), "film_id": "Q949228", "film": film()}
    for _ in range(30):
        await asha.ok("post", "/v1/films/send", body, status=201)
    assert (await asha.post("/v1/films/send", body)).status_code == 429


async def test_feed_pages(world):
    olive = await world.user("olive", visibility="friends")
    fred = await world.user("fred")
    await world.friends(olive, fred)
    base = datetime.now(UTC) - timedelta(hours=1)
    for i in range(5):
        # One push per stub: each takes the next feed_seq, so the order is the push order.
        await olive.push(stub(f"s{i}", f"Q{100 + i}", date=today(), at=base))
    pages, cursor = [], None
    while True:
        params = {"limit": 2} | ({"cursor": cursor} if cursor else {})
        page = await fred.ok("get", "/v1/feed", **params)
        pages.append([i["film_id"] for i in page["items"]])
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert pages == [["Q104", "Q103"], ["Q102", "Q101"], ["Q100"]]  # newest first, no repeats
    bad = await fred.get("/v1/feed", cursor="@@@")
    assert bad.status_code == 400 and bad.json()["error"]["code"] == "bad_cursor"
    shelf = await fred.ok("get", f"/v1/users/{olive.id}/films", limit=2)
    assert len(shelf["items"]) == 2 and shelf["next_cursor"]
    rest = await fred.ok("get", f"/v1/users/{olive.id}/films", limit=2, cursor=shelf["next_cursor"])
    assert len(rest["items"]) == 2
    last = await fred.ok("get", f"/v1/users/{olive.id}/films", limit=2, cursor=rest["next_cursor"])
    assert len(last["items"]) == 1 and last["next_cursor"] is None
    seen = [i["film_id"] for page in (shelf, rest, last) for i in page["items"]]
    assert len(set(seen)) == 5


async def test_reports_are_stored_and_limited(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    await ravi.ok("post", f"/v1/groups/{gid}/messages", {"body": "rude words"}, status=201)
    message_id = await world.value("select id from messages where kind = 'text'")
    user_report = await asha.ok(
        "post",
        "/v1/reports",
        {"kind": "user", "target_id": str(ravi.id), "reason": "spam", "note": None},
    )
    message_report = await asha.ok(
        "post",
        "/v1/reports",
        {"kind": "message", "target_id": str(message_id), "reason": "abuse", "note": "rude"},
    )
    group_report = await asha.ok(
        "post", "/v1/reports", {"kind": "group", "target_id": gid, "reason": "other", "note": None}
    )
    assert set(user_report) == {"id"}
    rows = {r["kind"]: r for r in await world.rows("select * from reports")}
    assert rows["user"]["target_user_id"] == ravi.id and rows["user"]["snapshot"] is None
    assert rows["message"]["snapshot"]["body"] == "rude words"
    assert rows["message"]["target_user_id"] == ravi.id and rows["message"]["note"] == "rude"
    assert rows["group"]["snapshot"] == {"name": "Crew"}
    assert str(rows["message"]["id"]) == message_report["id"] and group_report["id"]
    bad = [
        {"kind": "user", "target_id": "not-a-uuid"},
        {"kind": "user", "target_id": str(asha.id)},
        {"kind": "user", "target_id": "5c8a1f43-0000-4000-8000-000000000000"},
        {"kind": "message", "target_id": "99999"},
        {"kind": "message", "target_id": "abc"},
        {"kind": "group", "target_id": "5c8a1f43-0000-4000-8000-000000000000"},
    ]
    expected = [422, 422, 404, 404, 422, 404]
    for body, status in zip(bad, expected, strict=True):
        reply = await asha.post("/v1/reports", {**body, "reason": "spam", "note": None})
        assert reply.status_code == status, body
    # The limit is 20 an hour. Nine calls are in (3 stored, 6 refused): start a new hour.
    world.clock.advance(3601)
    for _ in range(20):
        await asha.ok(
            "post",
            "/v1/reports",
            {"kind": "user", "target_id": str(ravi.id), "reason": "spam", "note": None},
        )
    limited = await asha.post(
        "/v1/reports", {"kind": "user", "target_id": str(ravi.id), "reason": "spam", "note": None}
    )
    assert limited.status_code == 429
