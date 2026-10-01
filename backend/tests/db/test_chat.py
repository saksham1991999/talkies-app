"""Group chat: pages by cursor, system messages, blocks, limits."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from tests.db.conftest import film


async def say(client, gid, body, **extra):
    return await client.ok(
        "post", f"/v1/groups/{gid}/messages", {"body": body, **extra}, status=201
    )


async def test_post_and_read(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    sent = await say(ravi, gid, " Saturday works for me ")
    assert (sent["kind"], sent["body"], sent["code"], sent["args"]) == (
        "text",
        "Saturday works for me",
        None,
        None,
    )
    assert (
        sent["sender"]["handle"] == "ravi" and sent["film_id"] is None and sent["night_id"] is None
    )
    assert sent["created_at"].endswith("Z") and isinstance(sent["id"], int)
    listed = await asha.ok("get", f"/v1/groups/{gid}/messages")
    kinds = [(m["kind"], m["code"], m["body"]) for m in listed["items"]]
    assert kinds == [("system", "joined", None), ("text", None, "Saturday works for me")]
    assert listed["items"][0]["sender"] is None and listed["items"][0]["args"] == {"name": "Ravi"}
    assert listed["has_more"] is False
    assert [m["id"] for m in listed["items"]] == sorted(
        m["id"] for m in listed["items"]
    )  # oldest first


async def test_messages_can_carry_a_film_and_a_night(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    start = (datetime.now(UTC) + timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    night = await asha.ok(
        "post",
        f"/v1/groups/{gid}/nights",
        {
            "films": [{"film_id": "Q1", "film": film("Q1")}],
            "slots": [start],
            "tz_offset_min": 0,
            "place": None,
        },
        status=201,
    )
    both = await say(ravi, gid, "This one?", film_id="Q1", film=film("Q1"), night_id=night["id"])
    assert (both["film_id"], both["film"], both["night_id"]) == ("Q1", film("Q1"), night["id"])
    for extra in (
        {"film_id": "Q1"},  # a film id without the film
        {"film": film("Q1")},  # the film without its id
        {"film_id": "Q2", "film": film("Q1")},  # not the same film
        {"film_id": "my:dev.1", "film": film("Q1")},
        {"night_id": str(uuid4())},  # not a night of this group
    ):
        reply = await ravi.post(f"/v1/groups/{gid}/messages", {"body": "x", **extra})
        assert reply.status_code == 422, extra
    for body in ("", "   ", "x" * 1001, "a\x00b"):
        assert (await ravi.post(f"/v1/groups/{gid}/messages", {"body": body})).status_code == 422


async def test_pages_by_cursor(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    ids = [(await say(ravi, gid, f"message {i}"))["id"] for i in range(7)]
    world.clock.advance(61)

    async def page(**params):
        return await asha.ok("get", f"/v1/groups/{gid}/messages", **params)

    latest = await page(limit=3)  # no ids: the latest page, oldest first inside it
    assert [m["body"] for m in latest["items"]] == ["message 4", "message 5", "message 6"]
    assert latest["has_more"] is True
    older = await page(limit=3, before=latest["items"][0]["id"])
    assert [m["body"] for m in older["items"]] == ["message 1", "message 2", "message 3"]
    assert older["has_more"] is True
    oldest = await page(limit=3, before=older["items"][0]["id"])
    assert [m["body"] for m in oldest["items"]] == [
        None,
        "message 0",
    ]  # the "joined" notice, then 0
    assert oldest["has_more"] is False
    newer = await page(limit=2, after=ids[1])  # polling: everything after the last id I have
    assert [m["body"] for m in newer["items"]] == ["message 2", "message 3"]
    assert newer["has_more"] is True
    rest = await page(after=ids[3])
    assert [m["body"] for m in rest["items"]] == ["message 4", "message 5", "message 6"]
    assert rest["has_more"] is False
    assert (await page(after=ids[-1]))["items"] == []
    assert (await asha.get(f"/v1/groups/{gid}/messages", after=1, before=9)).status_code == 422
    assert (await asha.get(f"/v1/groups/{gid}/messages", limit=101)).status_code == 422
    sam = await world.user("sam")
    assert (await sam.get(f"/v1/groups/{gid}/messages")).status_code == 404
    assert (await sam.post(f"/v1/groups/{gid}/messages", {"body": "hi"})).status_code == 404


async def test_a_blocked_users_messages_are_hidden_both_ways(world):
    olive, fred, meena = [await world.user(n) for n in ("olive", "fred", "meena")]
    group = await world.group(olive, "Crew", fred, meena)
    gid = group["id"]
    await say(olive, gid, "from olive")
    await say(fred, gid, "from fred")
    await say(meena, gid, "from meena")
    await olive.ok("post", "/v1/blocks", {"user_id": str(fred.id)}, status=204)

    async def bodies(client):
        listed = await client.ok("get", f"/v1/groups/{gid}/messages")
        return [m["body"] for m in listed["items"] if m["body"]]

    assert await bodies(olive) == ["from olive", "from meena"]
    assert await bodies(fred) == ["from fred", "from meena"]
    assert await bodies(meena) == ["from olive", "from fred", "from meena"]
    # System messages have no sender, so they stay.
    listed = await olive.ok("get", f"/v1/groups/{gid}/messages")
    assert [m["code"] for m in listed["items"] if m["kind"] == "system"] == ["joined", "joined"]


async def test_system_messages_for_joins_leaves_and_nights(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    await ravi.ok("delete", f"/v1/groups/{gid}/members/me", status=204)
    system = await world.rows(
        "select code, args, sender_id, body from messages where kind = 'system' order by id"
    )
    assert [(r["code"], r["args"], r["sender_id"], r["body"]) for r in system] == [
        ("joined", {"name": "Ravi"}, None, None),
        ("left", {"name": "Ravi"}, None, None),
    ]


async def test_the_message_limit_is_30_a_minute(world):
    asha = await world.user("asha")
    group = await world.group(asha)
    gid = group["id"]
    for i in range(30):
        await say(asha, gid, f"m{i}")
    limited = await asha.post(f"/v1/groups/{gid}/messages", {"body": "one more"})
    assert limited.status_code == 429 and int(limited.headers["retry-after"]) >= 1
    world.clock.advance(61)
    await say(asha, gid, "later")


async def test_a_deleted_senders_messages_go_with_the_account(world):
    asha, ravi = await world.user("asha"), await world.user("ravi")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    await say(ravi, gid, "bye")
    await say(asha, gid, "stay")
    await ravi.ok("delete", "/v1/me", status=204)
    listed = await asha.ok("get", f"/v1/groups/{gid}/messages")
    assert [m["body"] for m in listed["items"] if m["body"]] == ["stay"]
