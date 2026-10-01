"""Blocks and reports: what a block deletes, what a report requires."""

from tests.db.conftest import film, stub, today


async def test_block_deletes_reactions_and_sent_films_both_ways(world):
    anna = await world.user("anna", visibility="friends")
    ben = await world.user("ben", visibility="friends")
    await world.friends(anna, ben)
    await ben.push(stub("b1", date=today()))
    await anna.push(stub("a1", "Q3", date=today()))
    await anna.ok(
        "put",
        "/v1/reactions",
        {"user_id": str(ben.id), "film_id": "Q949228", "reaction": 2},
        status=204,
    )
    await ben.ok(
        "put",
        "/v1/reactions",
        {"user_id": str(anna.id), "film_id": "Q3", "reaction": 4},
        status=204,
    )
    await anna.ok(
        "post",
        "/v1/films/send",
        {"user_id": str(ben.id), "film_id": "Q949228", "film": film(), "note": "hi"},
        status=201,
    )
    await ben.ok(
        "post",
        "/v1/films/send",
        {"user_id": str(anna.id), "film_id": "Q3", "film": film("Q3")},
        status=201,
    )

    await anna.ok("post", "/v1/blocks", {"user_id": str(ben.id)}, status=204)
    for table in ("reactions", "sent_films"):
        assert await world.value(f"select count(*) from {table}") == 0, table

    # Nothing comes back when the block is lifted.
    await anna.ok("delete", f"/v1/blocks/{ben.id}", status=204)
    for table in ("reactions", "sent_films"):
        assert await world.value(f"select count(*) from {table}") == 0, table


async def test_a_block_filters_the_counterpart_from_shared_groups(world):
    asha = await world.user("asha", visibility="friends")
    ravi = await world.user("ravi", visibility="friends")
    group = await world.group(asha, "Crew", ravi)
    gid = group["id"]
    deck = [{"film_id": "Q10", "film": film("Q10")}]
    await asha.ok("put", f"/v1/groups/{gid}/deck", {"base_version": 0, "items": deck})
    await ravi.ok(
        "put", f"/v1/groups/{gid}/swipes", {"swipes": [{"film_id": "Q10", "vote": "want"}]}
    )
    await ravi.ok("post", f"/v1/groups/{gid}/messages", {"body": "hello from ravi"}, status=201)

    await asha.ok("post", "/v1/blocks", {"user_id": str(ravi.id)}, status=204)
    # Ravi stays a member, but his contributions vanish from Asha's view.
    assert (await asha.ok("get", f"/v1/groups/{gid}"))["member_count"] == 2
    shown = await asha.ok("get", f"/v1/groups/{gid}/deck")
    assert shown["items"][0]["seen_by"] == 0
    tallies = await asha.ok("get", f"/v1/groups/{gid}/tallies")
    assert tallies["tallies"] == {}
    messages = await asha.ok("get", f"/v1/groups/{gid}/messages")
    assert messages["items"] == []
    # Ravi's view of his own swipes is untouched, and he still sees the deck.
    assert (await ravi.ok("get", f"/v1/groups/{gid}/tallies"))["tallies"]["Q10"]["want"] == 1


async def test_a_user_report_needs_a_relationship(world):
    anna = await world.user("anna", visibility="friends")
    ben = await world.user("ben", visibility="friends")
    cara = await world.user("cara")  # no relationship at all
    dave = await world.user("dave")
    await world.friends(anna, ben)
    await world.group(anna, "Crew", dave)
    report = {"reason": "spam", "note": None}

    stranger = await anna.post("/v1/reports", {"kind": "user", "target_id": str(cara.id), **report})
    assert stranger.status_code == 404
    assert await world.value("select count(*) from reports") == 0

    friend = await anna.ok(
        "post", "/v1/reports", {"kind": "user", "target_id": str(ben.id), **report}
    )
    groupmate = await anna.ok(
        "post", "/v1/reports", {"kind": "user", "target_id": str(dave.id), **report}
    )
    assert friend["id"] and groupmate["id"]
