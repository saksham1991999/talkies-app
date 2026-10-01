"""Phase 3 routes (groups, decks, swipes) against a scripted database."""

import re
from uuid import uuid4

from app.common import guest_color
from tests.helpers import auth, client_for, make_app, make_token
from tests.scripted import ScriptedConn, ScriptedDb

USER, OTHER = uuid4(), uuid4()
GID, M_OWNER, M_OTHER, M_GUEST = uuid4(), uuid4(), uuid4(), uuid4()
HEADERS = auth(make_token(USER))
FILM = {"id": "Q10", "t": "Ten", "l": ["hi"]}
GROUP = {"id": GID, "name": "Crew", "invite_code": "K7M2QX9P", "deck_version": 4, "member_count": 3}
OWNER_SEAT = {"id": M_OWNER, "owner": True}
MEMBER_SEAT = {"id": M_OTHER, "owner": False}


def app_for(*steps):
    conn = ScriptedConn(*steps)
    return make_app(db=ScriptedDb(conn)), conn


def member(
    mid, *, user_id=None, guest=None, handle=None, name=None, color=2, owner=False, me=False
):
    return {
        "id": mid,
        "user_id": user_id,
        "guest_name": guest,
        "handle": handle,
        "display_name": name,
        "avatar_color": color,
        "owner": owner,
        "me": me,
    }


async def test_group_detail_names_guests_and_users():
    members = [
        member(M_OWNER, user_id=USER, handle="asha", name="Asha", color=3, owner=True, me=True),
        member(M_OTHER, user_id=OTHER, handle="ravi", color=7),
        member(M_GUEST, guest="Dad"),
    ]
    app, conn = app_for(
        ("from group_members m join groups g", OWNER_SEAT),
        ("from groups g join group_decks", GROUP),
        ("left join profiles p", members),
    )
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}", headers=HEADERS)
    assert reply.status_code == 200, reply.text
    body = reply.json()
    assert {k: body[k] for k in ("name", "invite_code", "deck_version", "member_count")} == {
        "name": "Crew",
        "invite_code": "K7M2QX9P",
        "deck_version": 4,
        "member_count": 3,
    }
    assert body["members"] == [
        {
            "id": str(M_OWNER),
            "name": "Asha",
            "avatar_color": 3,
            "handle": "asha",
            "guest": False,
            "owner": True,
            "me": True,
        },
        {
            "id": str(M_OTHER),
            "name": "ravi",
            "avatar_color": 7,
            "handle": "ravi",
            "guest": False,
            "owner": False,
            "me": False,
        },
        {
            "id": str(M_GUEST),
            "name": "Dad",
            "avatar_color": guest_color("Dad"),
            "handle": None,
            "guest": True,
            "owner": False,
            "me": False,
        },
    ]
    assert conn.args_of("left join profiles p") == (GID, USER)
    conn.finished()


async def test_a_stranger_gets_404_not_403():
    app, _ = app_for(("from group_members m join groups g", None))
    async with client_for(app) as client:
        assert (await client.get(f"/v1/groups/{GID}", headers=HEADERS)).status_code == 404


async def test_only_the_owner_may_rename_rotate_delete_or_add_a_guest():
    for method, path, body in (
        ("patch", f"/v1/groups/{GID}", {"name": "New"}),
        ("delete", f"/v1/groups/{GID}", None),
        ("post", f"/v1/groups/{GID}/invite/rotate", None),
        ("post", f"/v1/groups/{GID}/guests", {"name": "Dad"}),
    ):
        steps = [("from group_members m join groups g", MEMBER_SEAT)]
        if path.endswith("guests"):
            steps.insert(0, ("for update", OTHER))  # the group row is locked first
        app, conn = app_for(*steps)
        async with client_for(app) as client:
            reply = await client.request(method.upper(), path, json=body, headers=HEADERS)
        assert reply.status_code == 403, path
        conn.finished()


async def test_create_a_group_retries_a_code_clash_and_keeps_the_limit():
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select count(*) from group_members where user_id", 3),
        ("insert into groups", None),  # the code was taken: try another
        ("insert into groups", GID),
        ("insert into group_members", "INSERT 0 1"),
        ("insert into group_decks", "INSERT 0 1"),
        ("from groups g join group_decks", {**GROUP, "member_count": 1, "deck_version": 0}),
    )
    async with client_for(app) as client:
        reply = await client.post("/v1/groups", json={"name": " Crew "}, headers=HEADERS)
    assert reply.status_code == 201, reply.text
    assert (reply.json()["name"], reply.json()["member_count"]) == ("Crew", 1)
    codes = [args[2] for kind, sql, args in conn.calls if "insert into groups" in sql]
    assert len(codes) == 2 and codes[0] != codes[1]
    assert all(re.fullmatch(r"[A-HJ-KM-NP-Z2-9]{8}", code) for code in codes)
    conn.finished()
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select count(*) from group_members where user_id", 20),
    )
    async with client_for(app) as client:
        reply = await client.post("/v1/groups", json={"name": "One more"}, headers=HEADERS)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "group_limit"


async def test_join_normalises_the_code_and_posts_one_notice():
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select id from groups where invite_code = $1 for update", GID),
        ("select 1 from group_members where group_id = $1 and user_id = $2", None),
        ("select count(*) from group_members where user_id", 2),
        ("select count(*) from group_members where group_id", 5),
        ("insert into group_members (group_id, user_id)", "INSERT 0 1"),
        ("select coalesce(display_name, handle, 'Member') from profiles", "Ravi"),
        ("insert into messages", "INSERT 0 1"),
        ("from groups g join group_decks", GROUP),
    )
    async with client_for(app) as client:
        reply = await client.post("/v1/groups/join", json={"code": " k7m2 qx9p "}, headers=HEADERS)
    assert reply.status_code == 200 and reply.json()["id"] == str(GID)
    assert conn.args_of("invite_code = $1 for update") == ("K7M2QX9P",)
    assert conn.args_of("insert into messages") == (GID, "joined", {"name": "Ravi"}, None, USER)
    conn.finished()


async def test_join_by_a_member_is_quiet_and_a_full_group_is_refused():
    again = [
        ("pg_advisory_xact_lock", None),
        ("insert into profiles", "INSERT 0 0"),
        ("select id from groups where invite_code", GID),
        ("select 1 from group_members where group_id = $1 and user_id = $2", 1),
        ("from groups g join group_decks", GROUP),
    ]
    app, conn = app_for(*again)
    async with client_for(app) as client:
        assert (
            await client.post("/v1/groups/join", json={"code": "K7M2QX9P"}, headers=HEADERS)
        ).status_code == 200
    conn.finished()
    full = [
        *again[:3],
        ("select 1 from group_members where group_id = $1 and user_id = $2", None),
        ("select count(*) from group_members where user_id", 1),
        ("select count(*) from group_members where group_id", 30),
    ]
    app, conn = app_for(*full)
    async with client_for(app) as client:
        reply = await client.post("/v1/groups/join", json={"code": "K7M2QX9P"}, headers=HEADERS)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "group_full"
    app, conn = app_for(*again[:2])  # a malformed code finds nothing
    async with client_for(app) as client:
        reply = await client.post("/v1/groups/join", json={"code": "ILLEGAL!"}, headers=HEADERS)
    assert reply.status_code == 404 and reply.json()["error"]["code"] == "invalid_code"
    conn.finished()


async def test_the_owner_leaving_hands_the_group_to_the_earliest_member():
    left = {"user_id": USER, "name": "Asha"}
    app, conn = app_for(
        ("select owner_id from groups where id = $1 for update", USER),
        ("from group_members m join groups g", OWNER_SEAT),
        ("from group_members m left join profiles p", left),
        ("delete from group_members", "DELETE 1"),
        ("select user_id from group_members where group_id", OTHER),
        ("update groups set owner_id", "UPDATE 1"),
        ("insert into messages", "INSERT 0 1"),
    )
    async with client_for(app) as client:
        reply = await client.delete(f"/v1/groups/{GID}/members/me", headers=HEADERS)
    assert reply.status_code == 204
    assert conn.args_of("update groups set owner_id") == (GID, OTHER)
    assert conn.args_of("insert into messages") == (GID, "left", {"name": "Asha"}, None, USER)
    conn.finished()
    # Nobody is left: the group goes, and no notice is written for a group that is gone.
    app, conn = app_for(
        ("select owner_id from groups where id = $1 for update", USER),
        ("from group_members m join groups g", OWNER_SEAT),
        ("from group_members m left join profiles p", left),
        ("delete from group_members", "DELETE 1"),
        ("select user_id from group_members where group_id", None),
        ("delete from groups where id", "DELETE 1"),
    )
    async with client_for(app) as client:
        assert (
            await client.delete(f"/v1/groups/{GID}/members/me", headers=HEADERS)
        ).status_code == 204
    conn.finished()


async def test_removing_someone_else_needs_the_owner_and_a_real_member_id():
    app, conn = app_for(
        ("for update", OTHER),
        ("from group_members m join groups g", MEMBER_SEAT),
        ("from group_members m left join profiles p", {"user_id": uuid4(), "name": "Meena"}),
    )
    async with client_for(app) as client:
        assert (
            await client.delete(f"/v1/groups/{GID}/members/{uuid4()}", headers=HEADERS)
        ).status_code == 403
    app, conn = app_for(("for update", OTHER), ("from group_members m join groups g", OWNER_SEAT))
    async with client_for(app) as client:
        assert (
            await client.delete(f"/v1/groups/{GID}/members/not-an-id", headers=HEADERS)
        ).status_code == 404
    app, conn = app_for(("for update", None))
    async with client_for(app) as client:
        assert (
            await client.delete(f"/v1/groups/{GID}/members/me", headers=HEADERS)
        ).status_code == 404


async def test_add_a_guest():
    app, conn = app_for(
        ("for update", USER),
        ("from group_members m join groups g", OWNER_SEAT),
        ("select count(*) from group_members where group_id", 4),
        ("lower(guest_name) = lower($2)", None),
        ("insert into group_members (group_id, guest_name)", M_GUEST),
    )
    async with client_for(app) as client:
        reply = await client.post(
            f"/v1/groups/{GID}/guests", json={"name": " Dad "}, headers=HEADERS
        )
    assert reply.status_code == 201
    assert reply.json() == {
        "id": str(M_GUEST),
        "name": "Dad",
        "avatar_color": guest_color("Dad"),
        "handle": None,
        "guest": True,
        "owner": False,
        "me": False,
    }
    conn.finished()
    for count, taken, code in ((30, None, "group_full"), (4, 1, "name_taken")):
        steps = [
            ("for update", USER),
            ("from group_members m join groups g", OWNER_SEAT),
            ("select count(*) from group_members where group_id", count),
        ]
        if count < 30:
            steps.append(("lower(guest_name) = lower($2)", taken))
        app, _ = app_for(*steps)
        async with client_for(app) as client:
            reply = await client.post(
                f"/v1/groups/{GID}/guests", json={"name": "Dad"}, headers=HEADERS
            )
        assert (reply.status_code, reply.json()["error"]["code"]) == (409, code)


async def test_shared_list_put_checks_capacity_only_for_a_new_film():
    base = [
        ("for update", USER),
        ("from group_members m join groups g", MEMBER_SEAT),
        ("select 1 from group_films", None),
    ]
    app, conn = app_for(
        *base, ("select count(*) from group_films", 199), ("insert into group_films", "INSERT 0 1")
    )
    async with client_for(app) as client:
        reply = await client.put(
            f"/v1/groups/{GID}/films/Q10", json={"film": FILM}, headers=HEADERS
        )
    assert reply.status_code == 204
    assert conn.args_of("insert into group_films") == (GID, "Q10", FILM)
    app, conn = app_for(*base, ("select count(*) from group_films", 200))
    async with client_for(app) as client:
        reply = await client.put(
            f"/v1/groups/{GID}/films/Q10", json={"film": FILM}, headers=HEADERS
        )
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "list_full"
    known = [*base[:2], ("select 1 from group_films", 1), ("insert into group_films", "INSERT 0 1")]
    app, conn = app_for(*known)
    async with client_for(app) as client:
        reply = await client.put(
            f"/v1/groups/{GID}/films/Q10", json={"film": FILM}, headers=HEADERS
        )
    assert reply.status_code == 204
    conn.finished()


DECK_ITEMS = [{"film_id": "Q10", "film": FILM}, {"film_id": "Q11", "film": {**FILM, "id": "Q11"}}]


async def test_get_deck_counts_who_has_seen_each_film():
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT),
        ("from group_decks where group_id", {"version": 4, "items": DECK_ITEMS}),
        ("group by film_id", [{"film_id": "Q11", "n": 2}]),
    )
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}/deck", headers=HEADERS)
    assert reply.status_code == 200, reply.text
    body = reply.json()
    assert body["version"] == 4
    assert [(i["film_id"], i["seen_by"]) for i in body["items"]] == [("Q10", 0), ("Q11", 2)]
    assert conn.args_of("group by film_id") == (GID, USER, ["Q10", "Q11"])
    conn.finished()


async def test_put_deck_versions_and_conflicts():
    body = {"base_version": 4, "items": DECK_ITEMS}
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT), ("update group_decks set version", 5)
    )
    async with client_for(app) as client:
        reply = await client.put(f"/v1/groups/{GID}/deck", json=body, headers=HEADERS)
    assert (reply.status_code, reply.json()) == (200, {"version": 5})
    gid, base, items = conn.args_of("update group_decks set version")
    assert (gid, base, items) == (GID, 4, DECK_ITEMS)
    app, _ = app_for(
        ("from group_members m join groups g", MEMBER_SEAT),
        ("update group_decks set version", None),
        ("select version from group_decks", 7),
    )
    async with client_for(app) as client:
        reply = await client.put(f"/v1/groups/{GID}/deck", json=body, headers=HEADERS)
    assert reply.status_code == 409
    assert reply.json()["error"] == {
        "code": "deck_conflict",
        "message": "The deck changed",
        "detail": {"current_version": 7},
    }


async def test_put_deck_is_one_write_per_ten_seconds_and_checks_its_items():
    app, conn = app_for(("from group_members m join groups g", MEMBER_SEAT))
    app.state.limiter.check("deck", f"{GID}:{USER}")
    async with client_for(app) as client:
        reply = await client.put(
            f"/v1/groups/{GID}/deck", json={"base_version": 4, "items": DECK_ITEMS}, headers=HEADERS
        )
    assert reply.status_code == 429 and "retry-after" in reply.headers
    app, conn = app_for()  # these never reach the database
    twice = [DECK_ITEMS[0], DECK_ITEMS[0]]
    mismatched = [{"film_id": "Q10", "film": {"id": "Q99", "t": "x"}}]
    async with client_for(app) as client:
        for items in (twice, mismatched, [{"film_id": "Q10", "film": {"id": "Q10"}}]):
            reply = await client.put(
                f"/v1/groups/{GID}/deck", json={"base_version": 4, "items": items}, headers=HEADERS
            )
            assert reply.status_code == 422
    conn.finished()


async def test_deck_inputs():
    taste = {"v": 1, "traits": {"g:drama": 80}}
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT),
        ("from v_group_tastes", [{"taste": taste}]),
        (
            "select film_id from ( select film_id from swipes",
            [{"film_id": "Q1"}, {"film_id": "Q2"}],
        ),
        ("from v_group_wishes", [{"film_id": "Q10", "film": FILM, "n": 3}]),
    )
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}/deck-inputs", headers=HEADERS)
    assert reply.json() == {
        "tastes": [taste],
        "seen": ["Q1", "Q2"],
        "wanted": [{"film_id": "Q10", "film": FILM, "n": 3}],
    }
    assert conn.args_of("select film_id from ( select film_id from swipes") == (GID, USER)
    conn.finished()


async def test_swipes_dedupe_and_resolve_the_acting_member():
    swipes = [
        {"film_id": "Q1", "vote": "skip"},
        {"film_id": "Q1", "vote": "want"},
        {"film_id": "Q2", "vote": "seen", "member_id": str(M_GUEST)},
        {"film_id": "Q3", "vote": "want", "member_id": str(M_OWNER)},
    ]
    app, conn = app_for(
        ("from group_members m join groups g", OWNER_SEAT),
        ("user_id is null", 1),  # the guest check runs once for the guest
        ("insert into swipes", "INSERT 0 3"),
    )
    async with client_for(app) as client:
        reply = await client.put(
            f"/v1/groups/{GID}/swipes", json={"swipes": swipes}, headers=HEADERS
        )
    assert (reply.status_code, reply.json()) == (200, {"saved": 3})
    gid, rows = conn.args_of("insert into swipes")
    assert gid == GID
    assert sorted((r["member_id"], r["film_id"], r["vote"]) for r in rows) == sorted(
        [
            (str(M_OWNER), "Q1", "want"),  # the last vote wins
            (str(M_GUEST), "Q2", "seen"),
            (str(M_OWNER), "Q3", "want"),
        ]
    )
    conn.finished()


async def test_swipes_for_another_member_are_403():
    for seat, target in ((MEMBER_SEAT, M_GUEST), (OWNER_SEAT, None)):
        steps = [("from group_members m join groups g", seat)]
        if seat is OWNER_SEAT:
            steps.append(("user_id is null", None))  # the target is an account, not a guest
            target = M_OTHER
        app, conn = app_for(*steps)
        body = {"swipes": [{"film_id": "Q1", "vote": "want", "member_id": str(target)}]}
        async with client_for(app) as client:
            reply = await client.put(f"/v1/groups/{GID}/swipes", json=body, headers=HEADERS)
        assert reply.status_code == 403
        conn.finished()


async def test_tallies():
    counts = [
        {"film_id": "Q1", "vote": "want", "n": 2},
        {"film_id": "Q1", "vote": "skip", "n": 1},
        {"film_id": "Q2", "vote": "seen", "n": 1},
    ]
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT),
        ("group by film_id, vote", counts),
        ("where member_id = $1", [{"film_id": "Q1", "vote": "want"}]),
    )
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}/tallies", headers=HEADERS)
    assert reply.json() == {
        "tallies": {
            "Q1": {"want": 2, "skip": 1, "seen": 0},
            "Q2": {"want": 0, "skip": 0, "seen": 1},
        },
        "mine": {"Q1": "want"},
    }
    assert conn.args_of("where member_id = $1") == (M_OTHER,)
    conn.finished()


async def test_my_groups_list():
    app, conn = app_for(("where g.id in (select group_id", [GROUP]))
    async with client_for(app) as client:
        reply = await client.get("/v1/groups", headers=HEADERS)
    assert reply.json()["items"][0]["invite_code"] == "K7M2QX9P"
    conn.finished()
