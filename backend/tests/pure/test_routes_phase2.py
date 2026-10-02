"""Phase 2 routes against a scripted database."""

from datetime import UTC, datetime
from uuid import uuid4

from app.logic.cursor import decode_cursor, encode_cursor
from app.logic.match import match_score
from tests.helpers import auth, client_for, make_app, make_token
from tests.scripted import ScriptedConn, ScriptedDb

USER, OTHER, THIRD = uuid4(), uuid4(), uuid4()
HEADERS = auth(make_token(USER))
FILM = {"id": "Q949228", "t": "Kantara", "g": ["drama"], "l": ["kn"]}


def app_for(*steps):
    conn = ScriptedConn(*steps)
    return make_app(db=ScriptedDb(conn)), conn


def person(uid, handle, name=None, color=2, **extra):
    return {"id": uid, "handle": handle, "display_name": name, "avatar_color": color, **extra}


def card(uid, handle, name=None, color=2):
    return {"id": str(uid), "handle": handle, "display_name": name, "avatar_color": color}


async def test_friend_list_scores_each_visible_friend_in_one_query():
    friends = [
        person(OTHER, "ravi", "Ravi", 7, visible=True, share_ratings=True),
        person(THIRD, "meena", "Meena", 1, visible=False, share_ratings=False),
        person(uuid4(), "dev", "Dev", 4, visible=True, share_ratings=False),
    ]
    matches = [
        {"owner_id": OTHER, "n_theirs": 20, "n_mine": 30, "common": [[4.0, 3.0], [None, 5.0]]}
    ]
    app, conn = app_for(("from friendships f join profiles p", friends), ("with mine as", matches))
    async with client_for(app) as client:
        reply = await client.get("/v1/friends", headers=HEADERS)
    assert reply.status_code == 200, reply.text
    items = reply.json()["items"]
    expected = match_score(30, 20, [(4.0, 3.0), (None, 5.0)], True)
    assert items[0] == {
        "card": card(OTHER, "ravi", "Ravi", 7),
        "visible": True,
        "match": {"both": 2, "pct": expected.pct},
    }
    assert items[1]["visible"] is False and items[1]["match"] is None  # not shared: no score
    assert items[2]["match"] == {"both": 0, "pct": None}  # shared, nothing in common
    owners = conn.args_of("with mine as")[1]
    assert owners == [OTHER, friends[2]["id"]]  # only friends who share are scored
    conn.finished()


async def test_friend_list_with_nobody_runs_no_match_query():
    app, conn = app_for(("from friendships f join profiles p", []))
    async with client_for(app) as client:
        reply = await client.get("/v1/friends", headers=HEADERS)
    assert reply.json() == {"items": []}
    conn.finished()


async def test_requests_pending_mutual_and_repeated():
    lock = ("pg_advisory_xact_lock", None)
    exists = ("from profiles p where p.id = $2", 1)
    app, conn = app_for(
        lock,
        exists,
        ("from friendships where user_id", None),
        ("from friend_requests where from_id = $1", None),
        ("delete from friend_requests where from_id = $2", None),
        ("insert into friend_requests", "INSERT 0 1"),
    )
    body = {"user_id": str(OTHER)}
    async with client_for(app) as client:
        reply = await client.post("/v1/friends/requests", json=body, headers=HEADERS)
    assert (reply.status_code, reply.json()) == (200, {"status": "pending"})
    assert conn.args_of("insert into friend_requests") == (USER, OTHER)
    # The two ids are locked in a fixed order, whoever asks first.
    assert conn.args_of("pg_advisory_xact_lock") == tuple(sorted((str(USER), str(OTHER))))
    conn.finished()

    app, conn = app_for(
        lock,
        exists,
        ("from friendships where user_id", None),
        ("from friend_requests where from_id = $1", None),
        ("delete from friend_requests where from_id = $2", 1),  # they asked me first
        ("insert into friendships", "INSERT 0 2"),
    )
    async with client_for(app) as client:
        reply = await client.post("/v1/friends/requests", json=body, headers=HEADERS)
    assert reply.json() == {"status": "friends"}
    conn.finished()

    app, _ = app_for(
        lock,
        exists,
        ("from friendships where user_id", None),
        ("from friend_requests where from_id = $1", 1),
    )
    async with client_for(app) as client:
        reply = await client.post("/v1/friends/requests", json=body, headers=HEADERS)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "already_pending"

    app, _ = app_for(lock, ("from profiles p where p.id = $2", None))
    async with client_for(app) as client:
        assert (
            await client.post("/v1/friends/requests", json=body, headers=HEADERS)
        ).status_code == 404

    app, conn = app_for()
    async with client_for(app) as client:
        own = await client.post(
            "/v1/friends/requests", json={"user_id": str(USER)}, headers=HEADERS
        )
    assert own.status_code == 422
    conn.finished()


async def test_friend_request_limit_is_30_an_hour():
    app, conn = app_for()
    for _ in range(30):
        app.state.limiter.check("friend_request", str(USER))
    async with client_for(app) as client:
        reply = await client.post(
            "/v1/friends/requests", json={"user_id": str(OTHER)}, headers=HEADERS
        )
    assert reply.status_code == 429 and "retry-after" in reply.headers
    conn.finished()


async def test_lookup_cleans_the_handle_and_hides_malformed_ones():
    row = person(OTHER, "asha_r", "Asha", 3, relation="outgoing")
    app, conn = app_for(("where p.handle = $2", row))
    async with client_for(app) as client:
        reply = await client.get(
            "/v1/users/lookup", params={"handle": " @Asha_R "}, headers=HEADERS
        )
    assert reply.json() == {"card": card(OTHER, "asha_r", "Asha", 3), "relation": "outgoing"}
    assert conn.args_of("where p.handle = $2") == (USER, "asha_r")
    app, conn = app_for(("where p.handle = $2", None))
    async with client_for(app) as client:
        assert (
            await client.get("/v1/users/lookup", params={"handle": "nobody"}, headers=HEADERS)
        ).status_code == 404
    conn.finished()
    app, conn = app_for()  # a malformed handle never reaches the database
    async with client_for(app) as client:
        for handle in ("a", "no spaces", "x" * 21, "bad!"):
            assert (
                await client.get("/v1/users/lookup", params={"handle": handle}, headers=HEADERS)
            ).status_code == 404
    conn.finished()


PROFILE_ROW = person(OTHER, "ravi", "Ravi", 7, visible=True, share_ratings=True)


def profile_steps(*, with_match=True):
    steps = [
        ("from v_audience a join profiles p", PROFILE_ROW),
        ("count(distinct film_id)", {"films": 12, "viewings": 15, "avg_rating": 3.456789}),
        (
            "jsonb_array_elements_text",
            [
                {"kind": "g", "name": "drama", "n": 5},
                {"kind": "g", "name": "action", "n": 5},
                {"kind": "g", "name": "comedy", "n": 2},
                {"kind": "g", "name": "war", "n": 1},
                {"kind": "l", "name": "hi", "n": 7},
                {"kind": "l", "name": "ta", "n": 7},
                {"kind": "l", "name": "kn", "n": 1},
                {"kind": "l", "name": "te", "n": 1},
            ],
        ),
        ("limit 10", [{"film_id": "Q949228", "film": FILM, "rating": 4.5}]),
        ("from v_visible_wishes", [{"film_id": "Q1", "film": {"id": "Q1", "t": "One"}}]),
    ]
    if with_match:
        steps.append(
            (
                "with mine as",
                [{"owner_id": OTHER, "n_theirs": 12, "n_mine": 9, "common": [[4.0, 4.5]]}],
            )
        )
    return steps


async def test_profile_view_of_a_friend():
    app, conn = app_for(*profile_steps())
    async with client_for(app) as client:
        reply = await client.get(f"/v1/users/{OTHER}", headers=HEADERS)
    assert reply.status_code == 200, reply.text
    view = reply.json()
    assert view["card"] == card(OTHER, "ravi", "Ravi", 7)
    assert (view["relation"], view["visible"]) == ("friend", True)
    assert view["stats"] == {
        "films": 12,
        "viewings": 15,
        "avg_rating": 3.46,
        "top_genres": ["action", "drama", "comedy"],  # most films first, ties by name
        "top_langs": ["hi", "ta", "kn"],
    }
    assert view["top_films"] == [{"film_id": "Q949228", "film": FILM, "rating": 4.5}]
    assert [w["film_id"] for w in view["watchlist"]] == ["Q1"]
    assert view["match"] == {"both": 1, "pct": match_score(9, 12, [(4.0, 4.5)], True).pct}
    assert conn.args_of("limit 10") == (
        USER,
        OTHER,
        True,
    )  # order by rating: the owner shares ratings
    conn.finished()


async def test_profile_view_of_myself_has_no_match_and_is_not_gated_on_sharing():
    steps = profile_steps(with_match=False)
    steps[0] = (steps[0][0], {**PROFILE_ROW, "id": USER, "visible": False, "share_ratings": False})
    steps[1] = (steps[1][0], {"films": 0, "viewings": 0, "avg_rating": None})
    app, conn = app_for(*steps)
    async with client_for(app) as client:
        view = (await client.get(f"/v1/users/{USER}", headers=HEADERS)).json()
    assert (view["relation"], view["visible"], view["match"]) == ("self", False, None)
    assert view["stats"]["avg_rating"] is None
    conn.finished()


async def test_profile_view_is_404_when_the_audience_row_is_missing():
    app, conn = app_for(("from v_audience a join profiles p", None))
    async with client_for(app) as client:
        reply = await client.get(f"/v1/users/{OTHER}", headers=HEADERS)
    assert reply.status_code == 404 and reply.json()["error"]["code"] == "not_found"
    conn.finished()


async def test_shelf_pages_by_offset_cursor():
    rows = [
        {"film_id": f"Q{i}", "film": {"id": f"Q{i}", "t": "x"}, "rating": None, "viewings": 1}
        for i in range(3)
    ]
    app, conn = app_for(("from v_audience where", 1), ("group by film_id", rows))
    async with client_for(app) as client:
        reply = await client.get(
            f"/v1/users/{OTHER}/films",
            params={"limit": 2, "cursor": encode_cursor(4)},
            headers=HEADERS,
        )
    body = reply.json()
    assert [i["film_id"] for i in body["items"]] == ["Q0", "Q1"]
    assert decode_cursor(body["next_cursor"]) == 6
    assert conn.args_of("group by film_id") == (USER, OTHER, 4, 3)
    app, _ = app_for(("from v_audience where", 1), ("group by film_id", rows[:1]))
    async with client_for(app) as client:
        last = (await client.get(f"/v1/users/{OTHER}/films", headers=HEADERS)).json()
    assert last["next_cursor"] is None
    app, conn = app_for(("from v_audience where", None))
    async with client_for(app) as client:
        assert (await client.get(f"/v1/users/{OTHER}/films", headers=HEADERS)).status_code == 404
    app, conn = app_for()  # my own shelf is built on the phone
    async with client_for(app) as client:
        assert (await client.get(f"/v1/users/{USER}/films", headers=HEADERS)).status_code == 404
        bad = await client.get(
            f"/v1/users/{OTHER}/films", params={"cursor": "***"}, headers=HEADERS
        )
    assert bad.status_code == 400 and bad.json()["error"]["code"] == "bad_cursor"
    conn.finished()


async def test_friends_who_watched():
    rows = [
        person(OTHER, "ravi", "Ravi", 7, rating=4.0),
        person(THIRD, "meena", None, 1, rating=None),
    ]
    app, conn = app_for(("where v.viewer_id = $1 and v.owner_id <> $1", rows))
    async with client_for(app) as client:
        reply = await client.get("/v1/films/Q949228/friends", headers=HEADERS)
    assert reply.json() == {
        "items": [
            {"user": card(OTHER, "ravi", "Ravi", 7), "rating": 4.0},
            {"user": card(THIRD, "meena", None, 1), "rating": None},
        ]
    }
    assert conn.args_of("v.owner_id <> $1") == (USER, "Q949228")
    async with client_for(app) as client:
        assert (await client.get("/v1/films/my:dev.1/friends", headers=HEADERS)).status_code == 422


def feed_row(src, seq, uid, handle, **extra):
    base = {
        "src": src,
        "feed_seq": seq,
        "film_id": "Q949228",
        "film": FILM,
        "rating": None,
        "reaction": None,
        "note": None,
        "my_reaction": None,
        **person(uid, handle, handle.title(), 5),
    }
    return {**base, **extra}


async def test_feed_items_ids_and_cursor():
    rows = [
        feed_row("w", 30, OTHER, "ravi", rating=4.0, my_reaction=2),
        feed_row("r", 20, THIRD, "meena", reaction=5),
        feed_row("s", 10, OTHER, "ravi", note="Watch this"),
    ]
    app, conn = app_for(("with watched as", rows))
    async with client_for(app) as client:
        reply = await client.get("/v1/feed", params={"limit": 2}, headers=HEADERS)
    body = reply.json()
    assert reply.status_code == 200, reply.text
    assert [(i["id"], i["kind"]) for i in body["items"]] == [
        ("w:30", "watched"),
        ("r:20", "reaction"),
    ]
    assert body["items"][0]["my_reaction"] == 2 and body["items"][1]["reaction"] == 5
    assert decode_cursor(body["next_cursor"]) == 20
    assert conn.args_of("with watched as") == (USER, None, 3)
    app, conn = app_for(("with watched as", rows[2:]))
    async with client_for(app) as client:
        last = (
            await client.get("/v1/feed", params={"cursor": encode_cursor(20)}, headers=HEADERS)
        ).json()
    assert last["next_cursor"] is None and last["items"][0]["note"] == "Watch this"
    assert conn.args_of("with watched as") == (USER, 20, 31)


async def test_reaction_put_and_clear():
    app, conn = app_for(("from v_visible_stubs", FILM), ("insert into reactions", "INSERT 0 1"))
    body = {"user_id": str(OTHER), "film_id": "Q949228", "reaction": 3}
    async with client_for(app) as client:
        reply = await client.put("/v1/reactions", json=body, headers=HEADERS)
    assert reply.status_code == 204
    assert conn.args_of("insert into reactions") == (USER, OTHER, "Q949228", FILM, 3)
    app, conn = app_for(("delete from reactions", "DELETE 1"))
    async with client_for(app) as client:
        reply = await client.put("/v1/reactions", json={**body, "reaction": None}, headers=HEADERS)
    assert reply.status_code == 204
    app, conn = app_for(("from v_visible_stubs", None))
    async with client_for(app) as client:
        assert (await client.put("/v1/reactions", json=body, headers=HEADERS)).status_code == 404
        assert (
            await client.put("/v1/reactions", json={**body, "reaction": 9}, headers=HEADERS)
        ).status_code == 422
        own = await client.put(
            "/v1/reactions", json={**body, "user_id": str(USER)}, headers=HEADERS
        )
    assert own.status_code == 422


async def test_block_removes_the_friendship_and_requests():
    app, conn = app_for(
        ("pg_advisory_xact_lock", None),  # the pair lock, shared with the friend routes
        ("select 1 from profiles", 1),
        ("insert into blocks", "INSERT 0 1"),
        ("delete from friendships", "DELETE 2"),
        ("delete from friend_requests", "DELETE 0"),
        ("delete from reactions", "DELETE 1"),
        ("delete from sent_films", "DELETE 1"),
    )
    async with client_for(app) as client:
        reply = await client.post("/v1/blocks", json={"user_id": str(OTHER)}, headers=HEADERS)
    assert reply.status_code == 204
    # The pair lock, with both ids sorted: the same key the friend routes take.
    assert conn.args_of("pg_advisory_xact_lock") == tuple(sorted((str(USER), str(OTHER))))
    assert conn.args_of("insert into blocks") == (USER, OTHER)
    conn.finished()


async def test_block_list_and_unblock():
    app, conn = app_for(
        ("from blocks b join profiles p", [person(OTHER, "ravi", "Ravi", 7)]),
        ("delete from blocks", "DELETE 1"),
    )
    async with client_for(app) as client:
        listed = await client.get("/v1/blocks", headers=HEADERS)
        gone = await client.delete(f"/v1/blocks/{OTHER}", headers=HEADERS)
    assert listed.json() == {"items": [card(OTHER, "ravi", "Ravi", 7)]}
    assert gone.status_code == 204


async def test_reports_store_a_snapshot_of_a_message_without_ids_objects():
    sent_at = datetime(2026, 10, 1, 12, 0, tzinfo=UTC)
    message = {
        "group_id": uuid4(),
        "sender_id": OTHER,
        "body": "rude words",
        "film_id": None,
        "night_id": None,
        "created_at": sent_at,
    }
    report_id = uuid4()
    app, conn = app_for(("from messages m", message), ("insert into reports", report_id))
    body = {"kind": "message", "target_id": "1042", "reason": "abuse", "note": "rude"}
    async with client_for(app) as client:
        reply = await client.post("/v1/reports", json=body, headers=HEADERS)
    assert reply.json() == {"id": str(report_id)}
    assert conn.args_of("from messages m") == (USER, 1042)
    args = conn.args_of("insert into reports")
    assert args[:6] == (USER, OTHER, "message", "1042", "abuse", "rude")
    assert args[6]["body"] == "rude words" and args[6]["sender_id"] == str(OTHER)
    assert args[6]["sent_at"] == sent_at.isoformat()
    conn.finished()


async def test_report_targets_are_checked():
    app, conn = app_for()
    async with client_for(app) as client:
        for kind, target in (
            ("user", "nope"),
            ("user", str(USER)),
            ("message", "abc"),
            ("group", "nope"),
        ):
            body = {"kind": kind, "target_id": target, "reason": "spam", "note": None}
            reply = await client.post("/v1/reports", json=body, headers=HEADERS)
            assert reply.status_code == 422, (kind, target)
    conn.finished()
