"""Phase 1 routes against a scripted database: order of calls, arguments, reply shape."""

from datetime import UTC, date, datetime, timedelta
from uuid import uuid4

import asyncpg

from tests.helpers import auth, client_for, make_app, make_token
from tests.scripted import ScriptedConn, ScriptedDb

USER = uuid4()
HEADERS = auth(make_token(USER))
KANTARA = {"id": "Q949228", "t": "Kantara", "y": 2022, "l": ["kn"]}
NOW = datetime.now(UTC)


def app_for(*steps):
    conn = ScriptedConn(*steps)
    return make_app(db=ScriptedDb(conn)), conn


def stub_record(sid="s1", at=None, **data):
    body = {"id": sid, "no": 1, "film": "Q949228", "date": NOW.date().isoformat(), "prec": "day"}
    return {
        "kind": "stub",
        "id": sid,
        "updated_at": (at or NOW).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "deleted": False,
        "film": KANTARA,
        "data": {**body, **data},
    }


ME_ROW = {
    "id": USER,
    "handle": None,
    "display_name": None,
    "avatar_color": 3,
    "visibility": "private",
    "share_ratings": False,
}


async def test_get_me_creates_the_profile_on_the_first_call():
    app, conn = app_for(
        ("from profiles where id = $1", None),
        ("insert into profiles", "INSERT 0 1"),
        ("from profiles where id = $1", ME_ROW),
    )
    async with client_for(app) as client:
        reply = await client.get("/v1/me", headers=HEADERS)
    assert reply.status_code == 200
    assert reply.json() == {**ME_ROW, "id": str(USER)}
    assert conn.args_of("insert into profiles") == (USER, USER.int % 11)
    conn.finished()


async def test_get_me_for_a_returning_user_is_one_query():
    app, conn = app_for(
        ("from profiles where id = $1", {**ME_ROW, "handle": "asha", "visibility": "friends"})
    )
    async with client_for(app) as client:
        reply = await client.get("/v1/me", headers=HEADERS)
    assert reply.json()["handle"] == "asha"
    conn.finished()


async def test_get_me_of_a_deleted_account_is_401():
    gone = asyncpg.ForeignKeyViolationError("profiles_id_fkey")
    app, _ = app_for(("from profiles where id = $1", None), ("insert into profiles", gone))
    async with client_for(app) as client:
        reply = await client.get("/v1/me", headers=HEADERS)
    assert reply.status_code == 401
    assert reply.json()["error"]["code"] == "account_deleted"


async def test_patch_me_sends_a_flag_and_a_value_for_each_field():
    row = {**ME_ROW, "handle": "asha_r", "visibility": "friends"}
    app, conn = app_for(("insert into profiles", "INSERT 0 0"), ("update profiles set", row))
    async with client_for(app) as client:
        reply = await client.patch(
            "/v1/me", json={"handle": "Asha_R", "visibility": "friends"}, headers=HEADERS
        )
    assert reply.status_code == 200 and reply.json()["handle"] == "asha_r"
    assert conn.args_of("update profiles set") == (
        USER,
        True, "asha_r",
        False, None,
        False, None,
        True, "friends",
        False, None,
    )  # fmt: skip


async def test_patch_me_can_clear_a_name_and_a_taken_handle_is_409():
    app, conn = app_for(("insert into profiles", "INSERT 0 0"), ("update profiles set", ME_ROW))
    async with client_for(app) as client:
        await client.patch("/v1/me", json={"display_name": None}, headers=HEADERS)
        assert conn.args_of("update profiles set")[3:5] == (True, None)
        taken = asyncpg.UniqueViolationError("profiles_handle_key")
        app, _ = app_for(("insert into profiles", "INSERT 0 0"), ("update profiles set", taken))
    async with client_for(app) as client:
        reply = await client.patch("/v1/me", json={"handle": "asha"}, headers=HEADERS)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "handle_taken"


async def test_patch_me_refuses_null_for_fields_that_cannot_be_null_and_unknown_keys():
    app, conn = app_for()
    async with client_for(app) as client:
        for body in (
            {"visibility": None},
            {"share_ratings": None},
            {"avatar_color": 11},
            {"role": "admin"},
        ):
            reply = await client.patch("/v1/me", json=body, headers=HEADERS)
            assert reply.status_code == 422, body
    conn.finished()


async def test_patch_me_reports_a_deletion_that_landed_mid_request():
    # ensure_profile ran, then a concurrent DELETE /v1/me took the row: the
    # update returns nothing and the reply must not be a 500.
    app, conn = app_for(("insert into profiles", "INSERT 0 1"), ("update profiles set", None))
    async with client_for(app) as client:
        reply = await client.patch("/v1/me", json={"display_name": "Asha"}, headers=HEADERS)
    assert reply.status_code == 401 and reply.json()["error"]["code"] == "account_deleted"
    conn.finished()


async def test_push_a_new_stub():
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select id from stubs where user_id = $1 and id = any", []),
        ("select count(*) from stubs", 5),
        ("insert into stubs", 41),
    )
    async with client_for(app) as client:
        reply = await client.post(
            "/v1/sync/push", json={"records": [stub_record(rating=4.5)]}, headers=HEADERS
        )
    assert reply.status_code == 200, reply.text
    body = reply.json()
    assert (body["conflicts"], body["rejected"]) == ([], [])
    assert body["server_time"].endswith("Z")
    args = conn.args_of("insert into stubs")
    assert args[0] == USER and args[1] == "s1" and args[2] == "Q949228"  # user, id, film_id
    assert args[3] == 4.5 and args[4] is False  # rating, private
    assert args[5] == NOW.date() and isinstance(args[5], date)  # watched_on
    assert args[6] == KANTARA and args[7]["film"] == "Q949228"  # film snapshot, data
    assert args[8].tzinfo is not None and args[9] is None  # updated_at, deleted_at
    assert args[10] is True  # fresh: it gets a feed_seq
    assert conn.args_of("pg_advisory_xact_lock") == (str(USER),)
    conn.finished()


async def test_push_reports_a_conflict_with_the_server_row_and_ignores_a_repeat():
    server = {
        "kind": "stub",
        "id": "s1",
        "updated_at": NOW + timedelta(minutes=1),
        "deleted": False,
        "film": KANTARA,
        "data": {"id": "s1", "film": "Q949228", "memo": "server"},
        "seq": 9,
    }
    same = {**server, "updated_at": NOW.replace(microsecond=0), "data": stub_record()["data"]}
    steps = [
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select id from stubs", [{"id": "s1"}]),
        ("select count(*) from stubs", 1),
        ("insert into stubs", None),
        ("from stubs where user_id = $1 and id = $2", server),
        ("not used", None),
        ("from stubs where user_id = $1 and id = $2", same),
    ]
    app, conn = app_for(*steps[:6])
    async with client_for(app) as client:
        reply = await client.post(
            "/v1/sync/push", json={"records": [stub_record()]}, headers=HEADERS
        )
    (conflict,) = reply.json()["conflicts"]
    assert (conflict["id"], conflict["seq"], conflict["data"]["memo"]) == ("s1", 9, "server")
    assert (
        conflict["updated_at"]
        == (NOW + timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    )
    # The server holds exactly what was pushed: a repeat, not a conflict.
    app, conn = app_for(*steps[:5], steps[7])
    async with client_for(app) as client:
        reply = await client.post(
            "/v1/sync/push", json={"records": [stub_record()]}, headers=HEADERS
        )
    assert reply.json()["conflicts"] == []


async def test_push_rejects_bad_records_without_touching_the_database_for_them():
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
    )
    bad = [stub_record("a", rating=9), stub_record("b", memo="m" * 17000)]
    async with client_for(app) as client:
        reply = await client.post("/v1/sync/push", json={"records": bad}, headers=HEADERS)
    assert reply.json()["rejected"] == [
        {"kind": "stub", "id": "a", "code": "invalid_record"},
        {"kind": "stub", "id": "b", "code": "too_large"},
    ]
    conn.finished()


async def test_push_of_each_kind_uses_its_own_table():
    meta = {
        "kind": "meta",
        "id": "meta",
        "updated_at": NOW.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "deleted": False,
        "film": None,
        "data": {"tags": [], "venues": [], "hidden": []},
    }
    wish = {
        **stub_record(),
        "kind": "wish",
        "id": "Q949228",
        "data": {"film": "Q949228", "added": "x"},
    }
    tomb = {**stub_record("gone"), "deleted": True, "film": None, "data": {}}
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select id from stubs", []),
        ("select count(*) from stubs", 0),
        ("select film_id as id from wishes", []),
        ("select count(*) from wishes", 0),
        ("insert into wishes", 1),
        ("insert into user_docs", 2),
        ("insert into stubs", 3),
    )
    async with client_for(app) as client:
        reply = await client.post(
            "/v1/sync/push", json={"records": [wish, meta, tomb]}, headers=HEADERS
        )
    assert reply.status_code == 200 and reply.json()["rejected"] == []
    assert conn.args_of("insert into user_docs")[:2] == (USER, "meta")
    stub_args = conn.args_of("insert into stubs")
    assert stub_args[1] == "gone" and stub_args[2] is None and stub_args[7] == {}  # tombstone
    assert stub_args[9] is not None  # deleted_at is the tombstone time
    assert stub_args[10] is False  # no feed_seq for a deleted stub
    conn.finished()


async def test_push_over_the_batch_limit_is_413_before_any_query():
    app, conn = app_for()
    records = [stub_record(f"s{i}") for i in range(201)]
    async with client_for(app) as client:
        reply = await client.post("/v1/sync/push", json={"records": records}, headers=HEADERS)
    assert reply.status_code == 413 and reply.json()["error"]["code"] == "too_large"
    conn.finished()


async def test_the_row_limit_rejects_new_stubs_only(monkeypatch):
    monkeypatch.setattr("app.routers.sync.MAX_ROWS", 2)
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select id from stubs", [{"id": "old"}]),
        ("select count(*) from stubs", 2),
        ("insert into stubs", 7),  # "old" is an edit: it goes through
    )
    records = [stub_record("old"), stub_record("new")]
    async with client_for(app) as client:
        reply = await client.post("/v1/sync/push", json={"records": records}, headers=HEADERS)
    assert reply.json()["rejected"] == [{"kind": "stub", "id": "new", "code": "limit_reached"}]
    conn.finished()


def pulled(kind, rid, seq, **fields):
    return {
        "kind": kind,
        "id": rid,
        "updated_at": NOW,
        "deleted": False,
        "film": None,
        "data": {},
        "seq": seq,
        **fields,
    }


async def test_pull_pages_and_the_cursor():
    rows = [
        pulled("stub", "s1", 5, film=KANTARA),
        pulled("wish", "Q1", 6),
        pulled("meta", "meta", 8),
    ]
    app, conn = app_for(("seq > $2", rows))
    async with client_for(app) as client:
        reply = await client.get("/v1/sync/pull", params={"after": 4, "limit": 2}, headers=HEADERS)
    body = reply.json()
    assert [(r["id"], r["seq"]) for r in body["records"]] == [("s1", 5), ("Q1", 6)]
    assert (body["cursor"], body["more"]) == (6, True)
    assert conn.args_of("seq > $2") == (USER, 4, 3)  # one row more than asked, to know `more`
    app, _ = app_for(("seq > $2", []))
    async with client_for(app) as client:
        empty = (await client.get("/v1/sync/pull", params={"after": 40}, headers=HEADERS)).json()
    assert (empty["records"], empty["cursor"], empty["more"]) == ([], 40, False)


async def test_pull_checks_its_query_parameters():
    app, _ = app_for()
    async with client_for(app) as client:
        for params in ({"after": -1}, {"limit": 0}, {"limit": 501}, {"after": "x"}):
            reply = await client.get("/v1/sync/pull", params=params, headers=HEADERS)
            assert reply.status_code == 422, params


async def test_delete_me_calls_supabase_first_then_deletes_the_data():
    order = []

    def handler(request):
        order.append(("auth", request.method, request.url.path))
        import httpx

        return httpx.Response(200, json={})

    class Tracking(ScriptedConn):
        async def execute(self, sql, *args):
            order.append(("db", sql.strip()[:30]))
            return await super().execute(sql, *args)

    conn = Tracking(
        ("pg_advisory_xact_lock", None),
        ("from profiles where id = $1", None),
        ("select delete_account($1)", None),
    )
    app = make_app(handler=handler, db=ScriptedDb(conn))
    async with client_for(app) as client:
        reply = await client.delete("/v1/me", headers=HEADERS)
    assert reply.status_code == 204
    assert order == [
        # The user lock is taken before the auth user goes, so a sync push that
        # is in flight cannot land between the two steps.
        ("db", "select pg_advisory_xact_lock(h"),
        ("auth", "DELETE", f"/auth/v1/admin/users/{USER}"),
        ("db", "select delete_account($1)"),
    ]
    conn.finished()
