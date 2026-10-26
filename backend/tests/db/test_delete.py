"""Deleting an account removes everything that points at it."""

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID

import asyncpg
import pytest

from tests.db.conftest import film, iso, stub, today, wish


async def seed_everything(world):
    """Alice (who will leave) is in every table. The others must keep what is theirs."""
    alice = await world.user("alice", visibility="friends", share_ratings=True)
    bob = await world.user("bob", visibility="friends")
    carol, dave, erin, frank = [await world.user(n) for n in ("carol", "dave", "erin", "frank")]
    await world.friends(alice, bob)
    await carol.ok("post", "/v1/friends/requests", {"user_id": str(alice.id)})  # pending, to Alice
    await alice.ok(
        "post", "/v1/friends/requests", {"user_id": str(frank.id)}
    )  # pending, from Alice
    await alice.ok("post", "/v1/blocks", {"user_id": str(dave.id)}, status=204)
    await erin.ok("post", "/v1/blocks", {"user_id": str(alice.id)}, status=204)
    later = iso(datetime.now(UTC) + timedelta(minutes=1))
    doc = {"updated_at": later, "deleted": False, "film": None}
    docs = [
        {**doc, "kind": "meta", "id": "meta", "data": {"tags": ["a"], "venues": [], "hidden": []}},
        {**doc, "kind": "taste", "id": "taste", "data": {"v": 1, "traits": {}}},
    ]
    await alice.push(
        stub("a1", date=today(), rating=4.0), stub("a2", "Q2", date=today()), wish("Q4"), *docs
    )
    await bob.push(stub("b1", "Q3", date=today()))
    # Reactions and sent films, both ways.
    await bob.ok(
        "put",
        "/v1/reactions",
        {"user_id": str(alice.id), "film_id": "Q949228", "reaction": 2},
        status=204,
    )
    await alice.ok(
        "put", "/v1/reactions", {"user_id": str(bob.id), "film_id": "Q3", "reaction": 4}, status=204
    )
    await alice.ok(
        "post",
        "/v1/films/send",
        {"user_id": str(bob.id), "film_id": "Q949228", "film": film(), "note": "hi"},
        status=201,
    )
    await bob.ok(
        "post",
        "/v1/films/send",
        {"user_id": str(alice.id), "film_id": "Q3", "film": film("Q3")},
        status=201,
    )
    # Three groups: Alice owns one with Bob, one alone; Bob owns one that Alice is in.
    g1 = await world.group(alice, "Alice and Bob", bob)
    g2 = await world.group(alice, "Alice alone")
    g3 = await world.group(bob, "Bob's", alice)
    for client, group in ((alice, g1), (bob, g3)):
        gid = group["id"]
        await client.ok("put", f"/v1/groups/{gid}/films/Q5", {"film": film("Q5")}, status=204)
        await client.ok(
            "put", f"/v1/groups/{gid}/swipes", {"swipes": [{"film_id": "Q5", "vote": "want"}]}
        )
    await alice.ok("post", f"/v1/groups/{g1['id']}/guests", {"name": "Dad"}, status=201)
    await alice.ok(
        "put", f"/v1/groups/{g3['id']}/swipes", {"swipes": [{"film_id": "Q6", "vote": "seen"}]}
    )
    deck = [{"film_id": "Q5", "film": film("Q5")}]
    await alice.ok("put", f"/v1/groups/{g1['id']}/deck", {"base_version": 0, "items": deck})
    for client, group in ((alice, g1), (bob, g1), (alice, g3), (bob, g3)):
        await client.ok(
            "post",
            f"/v1/groups/{group['id']}/messages",
            {"body": f"hello from {client.name}"},
            status=201,
        )
    # Nights: Alice hosts one in g1 and one in g3, with votes and an RSVP.
    start = iso(datetime.now(UTC) + timedelta(days=2))
    body = {
        "films": [{"film_id": "Q5", "film": film("Q5")}, {"film_id": "Q6", "film": film("Q6")}],
        "slots": [start],
        "tz_offset_min": 0,
        "place": None,
    }
    nights = []
    for group in (g1, g3):
        night = await alice.ok("post", f"/v1/groups/{group['id']}/nights", body, status=201)
        vote = {"option_ids": [night["options"][0]["id"]], "member_id": None}
        await alice.ok("put", f"/v1/nights/{night['id']}/votes", vote)
        nights.append(night)
    fixed = {**body, "films": body["films"][:1]}
    set_night = await alice.ok("post", f"/v1/groups/{g1['id']}/nights", fixed, status=201)
    await alice.ok(
        "put",
        f"/v1/nights/{set_night['id']}/rsvp",
        {"response": "yes", "member_id": None},
        status=204,
    )
    # Reports in both directions.
    report = {"reason": "spam", "note": None}
    await alice.ok("post", "/v1/reports", {"kind": "user", "target_id": str(bob.id), **report})
    await bob.ok("post", "/v1/reports", {"kind": "user", "target_id": str(alice.id), **report})
    message = await world.value("select id from messages where sender_id = $1 limit 1", alice.id)
    await bob.ok("post", "/v1/reports", {"kind": "message", "target_id": str(message), **report})
    return alice, bob, g1, g2, g3, nights


async def foreign_keys_to_profiles(world) -> list[tuple[str, str]]:
    rows = await world.rows(
        "select c.conrelid::regclass::text as tbl, a.attname as col "
        "from pg_constraint c "
        "join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey) "
        "where c.contype = 'f' and c.confrelid = 'public.profiles'::regclass"
    )
    return [(r["tbl"], r["col"]) for r in rows]


async def mentions_of(world, user_id: UUID) -> list[str]:
    """Every column of every table that still holds the user's id, as a uuid or as text.

    `reports_archive` is exempt: it keeps only minimal report fields after the
    account is gone (a user report keeps no account id; see
    test_the_report_archive_survives).
    """
    found = []
    columns = await world.rows(
        "select table_name, column_name from information_schema.columns "
        "where table_schema = 'public' and data_type in ('uuid', 'text', 'jsonb') "
        "and table_name in (select relname from pg_class where relkind = 'r') "
        "and table_name <> 'reports_archive'"
    )
    for row in columns:
        table, column = row["table_name"], row["column_name"]
        sql = f'select count(*) from "{table}" where "{column}"::text like $1'
        if await world.value(sql, f"%{user_id}%"):
            found.append(f"{table}.{column}")
    return found


async def test_deleting_an_account_leaves_no_row_that_points_at_it(world):
    alice, bob, g1, g2, g3, nights = await seed_everything(world)
    pairs = await foreign_keys_to_profiles(world)
    assert len(pairs) >= 20  # the introspection found the real schema
    for table, column in pairs:
        before = await world.value(f'select count(*) from {table} where "{column}" = $1', alice.id)
        assert before > 0, f"{table}.{column} was never seeded: the test would prove nothing"
    assert await mentions_of(world, alice.id)  # the seed put her id in many places

    reply = await alice.delete("/v1/me")
    assert reply.status_code == 204
    assert world.auth_deleted == [str(alice.id)]

    for table, column in pairs:
        after = await world.value(f'select count(*) from {table} where "{column}" = $1', alice.id)
        assert after == 0, f"{table}.{column} still points at the deleted account"
    assert await mentions_of(world, alice.id) == []
    assert await world.value("select count(*) from auth.users where id = $1", alice.id) == 0
    # Her name does not live on in notices either.
    notices = await world.rows("select args from messages where kind = 'system'")
    assert all("Alice" not in str(r["args"]) for r in notices)


async def test_what_belongs_to_other_people_stays(world):
    alice, bob, g1, g2, g3, nights = await seed_everything(world)
    await alice.ok("delete", "/v1/me", status=204)
    # Group 1 goes to Bob (the only linked member left). Group 2 had nobody else.
    assert await world.value("select owner_id from groups where id = $1", UUID(g1["id"])) == bob.id
    assert await world.value("select count(*) from groups where id = $1", UUID(g2["id"])) == 0
    assert await world.value("select owner_id from groups where id = $1", UUID(g3["id"])) == bob.id
    detail = await bob.ok("get", f"/v1/groups/{g1['id']}")
    assert [(m["name"], m["owner"], m["guest"]) for m in detail["members"]] == [
        ("Bob", True, False),
        ("Dad", False, True),
    ]
    assert (await bob.ok("get", f"/v1/groups/{g3['id']}"))["member_count"] == 1
    # Nights Alice hosted stay, without a host.
    for night in nights:
        shown = await bob.ok("get", f"/v1/nights/{night['id']}")
        assert shown["host_id"] is None
    # Bob keeps his diary, his own reactions' targets are gone, and chat holds only his lines.
    assert [r["id"] for r in (await bob.pull())["records"]] == ["b1"]
    assert await world.value("select count(*) from friendships") == 0
    texts = await world.rows("select body from messages where kind = 'text' order by id")
    assert {r["body"] for r in texts} == {"hello from bob"}
    assert await world.value("select count(*) from reports") == 0  # all of them involved Alice
    me = await bob.ok("get", "/v1/me")
    assert me["handle"] == "bob"


async def test_the_deleted_user_cannot_come_back_with_the_old_token(world):
    alice, bob, *_ = await seed_everything(world)
    await alice.ok("delete", "/v1/me", status=204)
    for reply in (
        await alice.get("/v1/me"),
        await alice.post("/v1/sync/push", {"records": [stub("x1")]}),
    ):
        assert reply.status_code == 401 and reply.json()["error"]["code"] == "account_deleted"
    assert await world.value("select count(*) from profiles where id = $1", alice.id) == 0
    # A surviving token must not resurrect the profile through another route either.
    await alice.ok("patch", "/v1/me", {"display_name": "Alice Again"}, status=401)
    assert await world.value("select count(*) from profiles where id = $1", alice.id) == 0
    assert await world.value("select count(*) from auth.users where id = $1", alice.id) == 0


async def test_a_token_dies_as_soon_as_the_auth_user_is_gone(world):
    """The auth delete commits before the local cleanup, so this window is real.

    A token is signed, not looked up, so nothing about it changes when Supabase
    forgets the account. Every route has to notice the missing account itself.
    """
    alice, bob, *_ = await seed_everything(world)
    # Exactly what a half-finished deletion looks like: Supabase is done, the
    # profile row (and everything the cascade owns) is still here. The FK to
    # auth.users cascades, so build the orphan with the triggers off.
    await world.pg.execute("set session_replication_role = replica")
    try:
        # The delete did not cascade (replica mode skips the FK), so the orphan
        # profile from a half-finished deletion is exactly what is left.
        await world.pg.execute("delete from auth.users where id = $1", alice.id)
    finally:
        await world.pg.execute("set session_replication_role = origin")
    assert await world.value("select count(*) from profiles where id = $1", alice.id) == 1
    assert await world.value("select count(*) from auth.users where id = $1", alice.id) == 0

    replies = [
        await alice.get("/v1/me"),
        await alice.post("/v1/sync/push", {"records": [stub("x1")]}),
        await alice.get("/v1/friends"),
        await alice.patch("/v1/me", {"display_name": "Alice Again"}),
    ]
    for reply in replies:
        assert reply.status_code == 401 and reply.json()["error"]["code"] == "account_deleted"
    # The token did not resurrect or change anything on the way out.
    assert await world.value("select count(*) from profiles where id = $1", alice.id) == 1
    assert await world.value("select count(*) from stubs where id = 'x1'") == 0
    # The delete itself is the one route that still gets through: it is the retry
    # that finishes this half-done cleanup, so it must not answer 401 while the
    # orphan is still there.
    await alice.ok("delete", "/v1/me", status=204)
    assert await world.value("select count(*) from profiles where id = $1", alice.id) == 0


async def test_a_failed_auth_delete_is_502_and_a_retry_finishes_the_job(world):
    alice, bob, *_ = await seed_everything(world)
    world.auth_status = 500
    reply = await alice.delete("/v1/me")
    assert reply.status_code == 502 and reply.json()["error"]["code"] == "upstream_unavailable"
    # The auth delete failed, so nothing was deleted and the account still works.
    assert await world.value("select count(*) from profiles where id = $1", alice.id) == 1
    assert await world.value("select count(*) from auth.users where id = $1", alice.id) == 1
    assert (await alice.get("/v1/me")).status_code == 200
    world.auth_status = 404  # Supabase says the user is gone: that counts as done
    assert (await alice.delete("/v1/me")).status_code == 204
    assert await world.value("select count(*) from profiles where id = $1", alice.id) == 0
    world.auth_status = 200
    assert (await alice.delete("/v1/me")).status_code == 204


async def test_the_report_archive_survives_a_deleted_account(world):
    alice, bob, *_ = await seed_everything(world)
    await alice.ok("delete", "/v1/me", status=204)
    # The reports cascade away, but the moderation trail stays, with no user id.
    assert await world.value("select count(*) from reports") == 0
    rows = await world.rows("select * from reports_archive order by reported_at")
    assert len(rows) >= 3
    assert {r["reason"] for r in rows} == {"spam"}
    assert {r["kind"] for r in rows} == {"user", "message"}
    assert all(r["target_id"] is None for r in rows if r["kind"] == "user")
    assert all(r["target_id"] for r in rows if r["kind"] != "user")
    assert all("@" not in (r["target_id"] or "") for r in rows)


async def test_the_delete_waits_for_a_sync_push_in_flight(world):
    alice = await world.user("alice")
    other = await asyncpg.connect(world.url)
    try:
        tx = other.transaction()
        await tx.start()  # a push of Alice's holds her lock
        await other.execute(
            "select pg_advisory_xact_lock(hashtextextended($1::text, 0))", str(alice.id)
        )
        task = asyncio.create_task(alice.delete("/v1/me"))
        done, _ = await asyncio.wait({task}, timeout=0.5)
        assert not done, "the delete did not wait for the user lock"
        await tx.commit()
        reply = await asyncio.wait_for(task, 10)
        assert reply.status_code == 204
    finally:
        await other.close()


async def test_the_hand_over_trigger_is_what_lets_an_owner_be_deleted(world):
    alice, bob, g1, *_ = await seed_everything(world)
    tx = world.pg.transaction()
    await tx.start()
    try:
        await world.pg.execute("alter table profiles disable trigger profiles_hand_over_groups")
        with pytest.raises(
            asyncpg.ForeignKeyViolationError
        ):  # owner_id is RESTRICT: it fails loudly
            await world.pg.execute("delete from profiles where id = $1", alice.id)
    finally:
        await tx.rollback()
    await world.pg.execute(
        "delete from profiles where id = $1", alice.id
    )  # with the trigger it works
    assert await world.value("select owner_id from groups where id = $1", UUID(g1["id"])) == bob.id
