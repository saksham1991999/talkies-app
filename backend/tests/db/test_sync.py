"""Sync against a real database: last write wins, limits, order, races."""

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from tests.db.conftest import Client, film, iso, stub, today, wish


def now() -> datetime:
    # Read the clock at call time, not at import time: this module runs last
    # in the db suite, and a stale timestamp makes the server-time wall and
    # the tombstone ordering below flake on slow machines.
    return datetime.now(UTC)


def parse(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


async def test_push_then_pull_round_trip(world):
    asha = await world.user("asha")
    record = stub("s1", date=today(), rating=4.5, memo="loved it", seat="F14")
    result = await asha.push(record)
    assert result["conflicts"] == [] and result["rejected"] == []
    assert parse(result["server_time"]) - now() < timedelta(minutes=1)
    pulled = await asha.pull()
    assert pulled["more"] is False
    (got,) = pulled["records"]
    assert (got["kind"], got["id"], got["deleted"]) == ("stub", "s1", False)
    assert got["data"] == record["data"]
    assert got["film"] == record["film"]
    assert got["updated_at"] == record["updated_at"]
    assert pulled["cursor"] == got["seq"] > 0
    assert (await asha.pull(after=pulled["cursor"]))["records"] == []
    assert (await asha.pull(after=pulled["cursor"]))["cursor"] == pulled["cursor"]


async def test_the_film_snapshot_keeps_only_known_keys(world):
    asha = await world.user("asha")
    record = stub("s1")
    record["film"] = {**film(), "memo": "CANARY", "date": "2001-01-01"}
    await asha.push(record)
    (got,) = (await asha.pull())["records"]
    assert got["film"] == film()


async def test_last_write_wins_and_a_tie_keeps_the_server_row(world):
    asha = await world.user("asha")
    base = now() - timedelta(hours=1)
    first = stub("s1", memo="first", at=base)
    await asha.push(first)

    older = await asha.push(stub("s1", memo="older", at=base - timedelta(minutes=5)))
    assert [c["data"]["memo"] for c in older["conflicts"]] == ["first"]

    tie = await asha.push(stub("s1", memo="tie", at=base))
    assert [c["data"]["memo"] for c in tie["conflicts"]] == ["first"]

    assert (await asha.push(first))["conflicts"] == []  # the same record again is not a conflict

    seq_before = (await asha.pull())["records"][0]["seq"]
    newer = await asha.push(stub("s1", memo="newer", at=base + timedelta(minutes=5)))
    assert newer["conflicts"] == []
    (got,) = (await asha.pull())["records"]
    assert got["data"]["memo"] == "newer"
    assert got["seq"] > seq_before


async def test_updated_at_is_clamped_to_five_minutes_ahead(world):
    asha = await world.user("asha")
    await asha.push(stub("s1", at=now() + timedelta(days=30)))
    (got,) = (await asha.pull())["records"]
    assert parse(got["updated_at"]) <= datetime.now(UTC) + timedelta(minutes=5, seconds=2)


async def test_a_tombstone_beats_an_older_create_and_loses_to_a_newer_one(world):
    asha = await world.user("asha")
    t0 = now() - timedelta(hours=1)
    tombstone = {
        "kind": "stub",
        "id": "s1",
        "updated_at": iso(t0),
        "deleted": True,
        "film": None,
        "data": {},
    }
    assert (await asha.push(tombstone))[
        "conflicts"
    ] == []  # a delete of a stub the server never saw
    result = await asha.push(stub("s1", at=t0 - timedelta(minutes=1)))
    assert [(c["id"], c["deleted"], c["film"], c["data"]) for c in result["conflicts"]] == [
        ("s1", True, None, {})
    ]
    (got,) = (await asha.pull())["records"]
    assert got["deleted"] is True and got["data"] == {} and got["film"] is None
    await asha.push(stub("s1", at=t0 + timedelta(minutes=1)))
    (got,) = (await asha.pull())["records"]
    assert got["deleted"] is False and got["data"]["film"] == "Q949228"


async def test_a_tombstone_drops_the_data(world):
    asha = await world.user("asha")
    await asha.push(stub("s1", memo="secret", at=now() - timedelta(hours=1)))
    tombstone = {**stub("s1", memo="still secret"), "deleted": True}
    await asha.push(tombstone)
    (got,) = (await asha.pull())["records"]
    assert got["deleted"] is True and got["data"] == {} and got["film"] is None
    assert "secret" not in str(await world.rows("select * from stubs where user_id = $1", asha.id))


async def test_bad_records_are_rejected_and_the_rest_is_saved(world):
    asha = await world.user("asha")
    no_film = {**stub("bad2"), "film": None}
    result = await asha.push(
        stub("good"),
        stub("bad1", rating=9),
        no_film,
        stub("bad3", memo="m" * 17000),
        stub("bad4", film_id="not-a-film"),
    )
    codes = {r["id"]: r["code"] for r in result["rejected"]}
    assert codes == {
        "bad1": "invalid_record",
        "bad2": "invalid_record",
        "bad3": "too_large",
        "bad4": "invalid_record",
    }
    assert [r["id"] for r in (await asha.pull())["records"]] == ["good"]


async def test_a_batch_over_200_is_413_and_200_is_fine(world):
    asha = await world.user("asha")
    reply = await asha.post("/v1/sync/push", {"records": [stub(f"s{i}") for i in range(201)]})
    assert reply.status_code == 413
    assert reply.json()["error"]["code"] == "too_large"
    assert (await asha.pull())["records"] == []
    result = await asha.push(*[stub(f"s{i}") for i in range(200)])
    assert result["rejected"] == [] and result["conflicts"] == []
    assert len((await asha.pull())["records"]) == 200


async def test_the_stub_limit(world, monkeypatch):
    monkeypatch.setattr("app.routers.sync.MAX_ROWS", 3)
    asha = await world.user("asha")
    base = now() - timedelta(hours=1)
    await asha.push(*[stub(f"s{i}", at=base) for i in range(3)])
    result = await asha.push(stub("s3"), stub("s0", memo="edit", at=base + timedelta(minutes=1)))
    assert result["rejected"] == [{"kind": "stub", "id": "s3", "code": "limit_reached"}]
    assert result["conflicts"] == []  # the edit of a stub we already hold goes through
    assert len((await asha.pull())["records"]) == 3


async def test_pull_pages(world):
    asha = await world.user("asha")
    await asha.push(*[stub(f"s{i}") for i in range(5)])
    seen, after, pages = [], 0, 0
    while True:
        page = await asha.pull(after=after, limit=2)
        pages += 1
        seen += [r["id"] for r in page["records"]]
        assert page["cursor"] == (page["records"][-1]["seq"] if page["records"] else after)
        if not page["more"]:
            break
        assert len(page["records"]) == 2
        after = page["cursor"]
    assert pages == 3
    assert sorted(seen) == [f"s{i}" for i in range(5)] and len(set(seen)) == 5
    seqs = [r["seq"] for r in (await asha.pull())["records"]]
    assert seqs == sorted(seqs)


async def test_feed_seq_rules(world):
    asha = await world.user("asha")
    old = (now() - timedelta(days=30)).date().isoformat()
    base = now() - timedelta(hours=1)
    await asha.push(
        stub("fresh", date=today(), at=base),
        stub("old", date=old, at=base),
        stub("private", date=today(), private=True, at=base),
        stub("month", date=today(), prec="month", at=base),
        stub("undated", at=base),
    )

    async def feed_seq(stub_id: str):
        sql = "select feed_seq from stubs where user_id = $1 and id = $2"
        return await world.value(sql, asha.id, stub_id)

    assert await feed_seq("fresh") is not None
    for name in ("old", "private", "month", "undated"):
        assert await feed_seq(name) is None, name
    first = await feed_seq("fresh")
    await asha.push(stub("fresh", date=today(), memo="edit", at=base + timedelta(minutes=1)))
    assert await feed_seq("fresh") == first  # an edit keeps it
    await asha.push(stub("fresh", date=today(), private=True, at=base + timedelta(minutes=2)))
    assert await feed_seq("fresh") is None  # private: out of every feed
    await asha.push(stub("fresh", date=today(), at=base + timedelta(minutes=3)))
    assert await feed_seq("fresh") > first  # public again: a new place at the top


async def test_two_pushes_at_once_do_not_interleave(world):
    asha = await world.user("asha")
    one = [stub(f"a{i}") for i in range(30)]
    two = [stub(f"b{i}") for i in range(30)]
    await asyncio.gather(asha.push(*one), asha.push(*two))
    seqs = {r["id"]: r["seq"] for r in (await asha.pull())["records"]}
    assert len(seqs) == 60
    for prefix in ("a", "b"):
        mine = sorted(seqs[f"{prefix}{i}"] for i in range(30))
        assert mine == list(range(mine[0], mine[0] + 30)), "the user lock keeps each push whole"


async def test_two_phones_pushing_the_same_stub_at_once_leave_one_winner(world):
    asha = await world.user("asha")
    base = now() - timedelta(hours=1)
    pushes = [
        asha.push(stub("s1", memo=f"phone {i}", at=base + timedelta(seconds=i))) for i in range(8)
    ]
    await asyncio.gather(*pushes)
    (got,) = (await asha.pull())["records"]
    assert got["data"]["memo"] == "phone 7"  # the newest `updated_at` wins whatever the order


async def test_wishes_meta_and_taste(world):
    asha = await world.user("asha")
    meta = {
        "kind": "meta",
        "id": "meta",
        "updated_at": iso(now()),
        "deleted": False,
        "film": None,
        "data": {"tags": ["a"], "venues": [{"name": "Home", "type": "home"}], "hidden": ["Q1"]},
    }
    taste = {**meta, "kind": "taste", "id": "taste", "data": {"v": 1, "traits": {"g:drama": 80}}}
    big = {**taste, "data": {"v": 1, "pad": "x" * 25000}}
    result = await asha.push(wish("Q5", planned="2026-12-01"), meta, taste)
    assert result["rejected"] == []
    assert (await asha.push(big))["rejected"] == [
        {"kind": "taste", "id": "taste", "code": "too_large"}
    ]
    records = {r["id"]: r for r in (await asha.pull())["records"]}
    assert set(records) == {"Q5", "meta", "taste"}
    assert records["meta"]["film"] is None and records["taste"]["data"]["v"] == 1
    assert records["Q5"]["data"]["planned"] == "2026-12-01"
    gone = {**wish("Q5", at=now() + timedelta(minutes=1)), "deleted": True, "film": None, "data": {}}
    await asha.push(gone)
    records = {r["id"]: r for r in (await asha.pull())["records"]}
    assert records["Q5"]["deleted"] is True and records["Q5"]["film"] is None


async def test_each_user_sees_only_their_own_rows(world):
    asha = await world.user("asha")
    ravi = await world.user("ravi")
    await asha.push(stub("s1"), wish("Q7"))
    assert (await ravi.pull())["records"] == []
    await ravi.push(stub("s1", memo="ravi's"))  # the same stub id in another diary is fine
    assert [r["data"].get("memo") for r in (await asha.pull())["records"] if r["id"] == "s1"] == [
        None
    ]


async def test_the_first_push_creates_the_profile(world):
    user_id = uuid4()
    await world.pg.execute("insert into auth.users (id, email) values ($1, 'new@x.test')", user_id)
    newcomer = Client(world.http, user_id, "new")
    await newcomer.push(stub("s1"))
    assert await world.value("select count(*) from profiles where id = $1", user_id) == 1
    me = await newcomer.ok("get", "/v1/me")
    assert me["visibility"] == "private" and me["share_ratings"] is False


async def test_a_deleted_account_gets_401_account_deleted(world):
    asha = await world.user("asha")
    await world.pg.execute(
        "delete from auth.users where id = $1", asha.id
    )  # Supabase removed the user
    reply = await asha.get("/v1/me")
    assert reply.status_code == 401
    assert reply.json()["error"]["code"] == "account_deleted"
    reply = await asha.post("/v1/sync/push", {"records": [stub("s1")]})
    assert reply.status_code == 401
    assert reply.json()["error"]["code"] == "account_deleted"
