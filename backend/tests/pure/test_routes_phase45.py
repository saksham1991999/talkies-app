"""Phase 4 and 5 routes (nights, chat, wrap-up, send a film) against a scripted database."""

import re
from datetime import UTC, date, datetime, timedelta
from uuid import uuid4

from tests.helpers import auth, client_for, make_app, make_token
from tests.scripted import ScriptedConn, ScriptedDb

USER, OTHER = uuid4(), uuid4()
GID, NID = uuid4(), uuid4()
M_OWNER, M_OTHER, M_GUEST = uuid4(), uuid4(), uuid4()
OPT_FILM, OPT_SLOT_1, OPT_SLOT_2 = uuid4(), uuid4(), uuid4()
HEADERS = auth(make_token(USER))
FILM = {"id": "Q10", "t": "Ten", "l": ["hi"]}
OWNER_SEAT = {"id": M_OWNER, "owner": True}
MEMBER_SEAT = {"id": M_OTHER, "owner": False}
SLOT_1 = datetime.now(UTC).replace(microsecond=0) + timedelta(days=2)
SLOT_2 = SLOT_1 + timedelta(days=1)


def stamp(moment: datetime) -> str:
    return moment.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def app_for(*steps):
    conn = ScriptedConn(*steps)
    return make_app(db=ScriptedDb(conn)), conn


def night_row(status="poll", host=USER):
    return {
        "id": NID,
        "group_id": GID,
        "host_id": host,
        "status": status,
        "tz_offset_min": 330,
        "place": "PVR",
    }


def option_row(oid, kind, position, approvals, *, chosen=False, film=False, at=None):
    return {
        "night_id": NID,
        "id": oid,
        "kind": kind,
        "position": position,
        "film_id": "Q10" if film else None,
        "film": FILM if film else None,
        "starts_at": at,
        "chosen": chosen,
        "approvals": approvals,
    }


def option_rows(*, chosen=False):
    return [
        option_row(OPT_FILM, "film", 0, 2, chosen=chosen, film=True),
        option_row(OPT_SLOT_1, "slot", 0, 2, chosen=chosen, at=SLOT_1),
        option_row(OPT_SLOT_2, "slot", 1, 1, at=SLOT_2),
    ]


def loader(status="poll", *, chosen=False, mine=(), rsvps=()):
    """The four queries that build a `night`."""
    return [
        ("from nights where id = any", [night_row(status)]),
        ("from night_options o where o.night_id = any", option_rows(chosen=chosen)),
        (
            "from night_votes v join night_options o",
            [{"night_id": NID, "option_id": o} for o in mine],
        ),
        ("from night_rsvps", [{"night_id": NID, "member_id": m, "response": r} for m, r in rsvps]),
    ]


def poll_body(films=2, slots=2):
    start = datetime.now(UTC) + timedelta(days=3)
    return {
        "films": [
            {"film_id": f"Q{10 + i}", "film": {"id": f"Q{10 + i}", "t": "x"}} for i in range(films)
        ],
        "slots": [stamp(start + timedelta(days=i)) for i in range(slots)],
        "tz_offset_min": 330,
        "place": "PVR",
    }


async def test_create_a_poll_night():
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT),
        ("insert into nights", NID),
        ("insert into night_options (night_id, kind, position, film_id", "INSERT 0 2"),
        ("insert into night_options (night_id, kind, position, starts_at", "INSERT 0 2"),
        ("insert into messages", "INSERT 0 1"),
        *loader(mine=[OPT_FILM]),
    )
    body = poll_body()
    async with client_for(app) as client:
        reply = await client.post(f"/v1/groups/{GID}/nights", json=body, headers=HEADERS)
    assert reply.status_code == 201, reply.text
    night = reply.json()
    assert (night["status"], night["host_id"], night["event"], night["mine"]) == (
        "poll",
        str(USER),
        None,
        [str(OPT_FILM)],
    )
    assert [(o["kind"], o["position"], o["approvals"]) for o in night["options"]] == [
        ("film", 0, 2),
        ("slot", 0, 2),
        ("slot", 1, 1),
    ]
    assert conn.args_of("insert into nights") == (GID, USER, "poll", 330, "PVR")
    _, films, chosen = conn.args_of("insert into night_options (night_id, kind, position, film_id")
    assert [(f["position"], f["film_id"]) for f in films] == [
        (0, "Q10"),
        (1, "Q11"),
    ] and chosen is False
    _, slots, _ = conn.args_of("insert into night_options (night_id, kind, position, starts_at")
    assert slots == [
        {"position": 0, "starts_at": body["slots"][0]},
        {"position": 1, "starts_at": body["slots"][1]},
    ]
    assert conn.args_of("insert into messages") == (
        GID,
        "poll_open",
        {"night_id": str(NID)},
        NID,
        None,
    )
    conn.finished()


async def test_one_film_and_one_slot_is_set_at_once_and_says_so():
    body = poll_body(films=1, slots=1)
    app, conn = app_for(
        ("from group_members m join groups g", OWNER_SEAT),
        ("insert into nights", NID),
        ("insert into night_options (night_id, kind, position, film_id", "INSERT 0 1"),
        ("insert into night_options (night_id, kind, position, starts_at", "INSERT 0 1"),
        ("insert into messages", "INSERT 0 1"),
        *loader("set", chosen=True),
    )
    async with client_for(app) as client:
        reply = await client.post(f"/v1/groups/{GID}/nights", json=body, headers=HEADERS)
    night = reply.json()
    assert night["status"] == "set"
    assert night["event"] == {
        "film_id": "Q10",
        "film": FILM,
        "starts_at": stamp(SLOT_1),
        "tz_offset_min": 330,
        "place": "PVR",
    }
    assert conn.args_of("insert into nights")[2] == "set"
    assert conn.args_of("insert into night_options (night_id, kind, position, film_id")[2] is True
    code, args = conn.args_of("insert into messages")[1:3]
    assert code == "night_set" and args == {
        "night_id": str(NID),
        "film_id": "Q10",
        "starts_at": body["slots"][0],
    }
    conn.finished()


async def test_slots_outside_the_window_and_repeats_are_422_before_the_database():
    now = datetime.now(UTC)
    app, conn = app_for()
    bad = [
        {**poll_body(), "slots": [stamp(now - timedelta(days=2))]},
        {**poll_body(), "slots": [stamp(now + timedelta(days=401))]},
        {**poll_body(), "slots": [stamp(now + timedelta(days=3))] * 2},
        {**poll_body(), "films": [poll_body()["films"][0]] * 2},
        {**poll_body(), "films": [{"film_id": "Q10", "film": {"id": "Q11", "t": "x"}}]},
    ]
    async with client_for(app) as client:
        for body in bad:
            reply = await client.post(f"/v1/groups/{GID}/nights", json=body, headers=HEADERS)
            assert reply.status_code == 422
    conn.finished()


async def test_list_nights():
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT),
        ("from nights where group_id", [{"id": NID}]),
        *loader("set", chosen=True, rsvps=[(M_OWNER, "yes"), (M_GUEST, "maybe")]),
    )
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}/nights", headers=HEADERS)
    (night,) = reply.json()["items"]
    assert night["rsvps"] == [
        {"member_id": str(M_OWNER), "response": "yes"},
        {"member_id": str(M_GUEST), "response": "maybe"},
    ]
    assert conn.args_of("from night_votes v join night_options o") == ([NID], M_OTHER)
    conn.finished()
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT), ("from nights where group_id", [])
    )
    async with client_for(app) as client:
        assert (await client.get(f"/v1/groups/{GID}/nights", headers=HEADERS)).json() == {
            "items": []
        }
    conn.finished()


NIGHT_OF = (
    "select group_id, host_id, status from nights where id = $1",
    {"group_id": GID, "host_id": USER, "status": "poll"},
)


async def test_get_night_for_a_guest_needs_the_owner():
    app, conn = app_for(
        NIGHT_OF,
        ("from group_members m join groups g", OWNER_SEAT),
        ("user_id is null", 1),
        *loader(),
    )
    async with client_for(app) as client:
        reply = await client.get(
            f"/v1/nights/{NID}", params={"member_id": str(M_GUEST)}, headers=HEADERS
        )
    assert reply.status_code == 200
    assert conn.args_of("from night_votes v join night_options o") == ([NID], M_GUEST)
    app, conn = app_for(NIGHT_OF, ("from group_members m join groups g", MEMBER_SEAT))
    async with client_for(app) as client:
        reply = await client.get(
            f"/v1/nights/{NID}", params={"member_id": str(M_GUEST)}, headers=HEADERS
        )
    assert reply.status_code == 403
    app, conn = app_for(("select group_id, host_id, status from nights where id = $1", None))
    async with client_for(app) as client:
        assert (await client.get(f"/v1/nights/{NID}", headers=HEADERS)).status_code == 404


async def test_put_votes_replaces_the_members_approvals():
    locked = ("select group_id, host_id, status from nights where id = $1 for update", NIGHT_OF[1])
    app, conn = app_for(
        locked,
        ("from group_members m join groups g", MEMBER_SEAT),
        ("select id from night_options where night_id", [{"id": OPT_FILM}, {"id": OPT_SLOT_1}]),
        ("delete from night_votes", "DELETE 1"),
        ("insert into night_votes", "INSERT 0 2"),
        ("count(v.member_id)", [{"id": OPT_FILM, "n": 3}, {"id": OPT_SLOT_1, "n": 1}]),
    )
    body = {"option_ids": [str(OPT_FILM), str(OPT_SLOT_1)], "member_id": None}
    async with client_for(app) as client:
        reply = await client.put(f"/v1/nights/{NID}/votes", json=body, headers=HEADERS)
    assert reply.json() == {"approvals": {str(OPT_FILM): 3, str(OPT_SLOT_1): 1}}
    assert conn.args_of("delete from night_votes") == (M_OTHER, NID)
    assert sorted(conn.args_of("insert into night_votes")[0]) == sorted([OPT_FILM, OPT_SLOT_1])
    conn.finished()
    foreign = {"option_ids": [str(uuid4())], "member_id": None}
    app, conn = app_for(
        locked,
        ("from group_members m join groups g", MEMBER_SEAT),
        ("select id from night_options", [{"id": OPT_FILM}]),
    )
    async with client_for(app) as client:
        assert (
            await client.put(f"/v1/nights/{NID}/votes", json=foreign, headers=HEADERS)
        ).status_code == 422
    closed = (
        "select group_id, host_id, status from nights where id = $1 for update",
        {**NIGHT_OF[1], "status": "set"},
    )
    app, conn = app_for(closed, ("from group_members m join groups g", MEMBER_SEAT))
    async with client_for(app) as client:
        reply = await client.put(f"/v1/nights/{NID}/votes", json=body, headers=HEADERS)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "not_polling"


async def test_close_takes_the_most_approved_and_the_host_may_override():
    locked = ("for update", NIGHT_OF[1])
    app, conn = app_for(
        locked,
        ("from group_members m join groups g", OWNER_SEAT),
        ("from night_options o where o.night_id = any", option_rows()),
        ("update night_options set chosen", "UPDATE 2"),
        ("update nights set status = 'set'", "UPDATE 1"),
        ("insert into messages", "INSERT 0 1"),
        *loader("set", chosen=True),
    )
    body = {"film_option_id": None, "slot_option_id": None, "place": "Inox"}
    async with client_for(app) as client:
        reply = await client.post(f"/v1/nights/{NID}/close", json=body, headers=HEADERS)
    assert reply.status_code == 200, reply.text
    assert sorted(conn.args_of("update night_options set chosen")[0]) == sorted(
        [OPT_FILM, OPT_SLOT_1]
    )
    assert conn.args_of("update nights set status = 'set'") == (NID, "Inox")
    assert conn.args_of("insert into messages")[1:3] == (
        "night_set",
        {"night_id": str(NID), "film_id": "Q10", "starts_at": stamp(SLOT_1)},
    )
    conn.finished()
    # The host picks slot 2 although slot 1 has more approvals. A film id for a slot is refused.
    app, conn = app_for(
        locked,
        ("from group_members m join groups g", OWNER_SEAT),
        ("from night_options o where o.night_id = any", option_rows()),
        ("update night_options set chosen", "UPDATE 2"),
        ("update nights set status = 'set'", "UPDATE 1"),
        ("insert into messages", "INSERT 0 1"),
        *loader("set", chosen=True),
    )
    async with client_for(app) as client:
        await client.post(
            f"/v1/nights/{NID}/close", json={"slot_option_id": str(OPT_SLOT_2)}, headers=HEADERS
        )
    assert sorted(conn.args_of("update night_options set chosen")[0]) == sorted(
        [OPT_FILM, OPT_SLOT_2]
    )
    app, conn = app_for(
        locked,
        ("from group_members m join groups g", OWNER_SEAT),
        ("from night_options o where o.night_id = any", option_rows()),
    )
    async with client_for(app) as client:
        wrong = await client.post(
            f"/v1/nights/{NID}/close", json={"film_option_id": str(OPT_SLOT_1)}, headers=HEADERS
        )
    assert wrong.status_code == 422


async def test_close_needs_the_host_or_the_owner_and_a_poll():
    other_host = {**NIGHT_OF[1], "host_id": OTHER}
    app, conn = app_for(
        ("for update", other_host), ("from group_members m join groups g", MEMBER_SEAT)
    )
    async with client_for(app) as client:
        assert (
            await client.post(f"/v1/nights/{NID}/close", json={}, headers=HEADERS)
        ).status_code == 403
    done = {**NIGHT_OF[1], "status": "set"}
    app, conn = app_for(("for update", done), ("from group_members m join groups g", OWNER_SEAT))
    async with client_for(app) as client:
        reply = await client.post(f"/v1/nights/{NID}/close", json={}, headers=HEADERS)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "not_polling"


async def test_rsvp_and_delete():
    setn = {**NIGHT_OF[1], "status": "set"}
    app, conn = app_for(
        ("for update", setn),
        ("from group_members m join groups g", MEMBER_SEAT),
        ("insert into night_rsvps", "INSERT 0 1"),
    )
    async with client_for(app) as client:
        reply = await client.put(
            f"/v1/nights/{NID}/rsvp", json={"response": "maybe", "member_id": None}, headers=HEADERS
        )
    assert reply.status_code == 204
    assert conn.args_of("insert into night_rsvps") == (NID, M_OTHER, "maybe")
    app, conn = app_for(
        ("for update", NIGHT_OF[1]), ("from group_members m join groups g", MEMBER_SEAT)
    )
    async with client_for(app) as client:
        reply = await client.put(
            f"/v1/nights/{NID}/rsvp", json={"response": "yes", "member_id": None}, headers=HEADERS
        )
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "not_set"
    app, conn = app_for(
        NIGHT_OF,
        ("from group_members m join groups g", MEMBER_SEAT),
        ("delete from nights", "DELETE 1"),
    )
    async with client_for(app) as client:
        assert (
            await client.delete(f"/v1/nights/{NID}", headers=HEADERS)
        ).status_code == 204  # USER is the host
    other_host = (
        "select group_id, host_id, status from nights where id = $1",
        {**NIGHT_OF[1], "host_id": OTHER},
    )
    app, conn = app_for(other_host, ("from group_members m join groups g", MEMBER_SEAT))
    async with client_for(app) as client:
        assert (await client.delete(f"/v1/nights/{NID}", headers=HEADERS)).status_code == 403


def message_row(mid, body="hi", *, sender=True, kind="text", code=None, args=None):
    return {
        "id": mid,
        "kind": kind,
        "body": body if sender else None,
        "code": code,
        "args": args,
        "film_id": None,
        "film": None,
        "night_id": None,
        "created_at": SLOT_1,
        "sender_id": OTHER if sender else None,
        "handle": "ravi" if sender else None,
        "display_name": "Ravi" if sender else None,
        "avatar_color": 7 if sender else None,
    }


async def test_message_pages():
    newest_first = [message_row(9, "c"), message_row(8, "b"), message_row(7, "a")]
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT), ("from messages m", newest_first)
    )
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}/messages", params={"limit": 2}, headers=HEADERS)
    body = reply.json()
    assert [m["id"] for m in body["items"]] == [8, 9]  # the page, oldest first
    assert body["has_more"] is True
    assert conn.args_of("from messages m") == (GID, None, None, USER, 3)
    oldest_first = [message_row(8, "b"), message_row(9, "c")]
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT), ("from messages m", oldest_first)
    )
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}/messages", params={"after": 7}, headers=HEADERS)
    assert [m["id"] for m in reply.json()["items"]] == [8, 9] and reply.json()["has_more"] is False
    assert conn.args_of("from messages m") == (GID, 7, None, USER, 31)
    app, conn = app_for()
    async with client_for(app) as client:
        both = await client.get(
            f"/v1/groups/{GID}/messages", params={"after": 1, "before": 5}, headers=HEADERS
        )
    assert both.status_code == 422


async def test_system_messages_have_no_sender():
    rows = [message_row(3, kind="system", sender=False, code="joined", args={"name": "Ravi"})]
    app, _ = app_for(("from group_members m join groups g", MEMBER_SEAT), ("from messages m", rows))
    async with client_for(app) as client:
        reply = await client.get(f"/v1/groups/{GID}/messages", headers=HEADERS)
    (message,) = reply.json()["items"]
    assert (message["sender"], message["body"], message["code"], message["args"]) == (
        None,
        None,
        "joined",
        {"name": "Ravi"},
    )


async def test_post_a_message():
    row = {"id": 12, "created_at": SLOT_1}
    me = {"id": USER, "handle": "asha", "display_name": "Asha", "avatar_color": 3}
    app, conn = app_for(
        ("from group_members m join groups g", MEMBER_SEAT),
        ("select 1 from nights where id = $1 and group_id = $2", 1),
        ("insert into messages", row),
        ("from profiles where id = $1", me),
    )
    body = {"body": " On Saturday? ", "film_id": "Q10", "film": FILM, "night_id": str(NID)}
    async with client_for(app) as client:
        reply = await client.post(f"/v1/groups/{GID}/messages", json=body, headers=HEADERS)
    assert reply.status_code == 201, reply.text
    sent = reply.json()
    assert (sent["id"], sent["body"], sent["kind"], sent["film"], sent["night_id"]) == (
        12,
        "On Saturday?",
        "text",
        FILM,
        str(NID),
    )
    assert sent["sender"]["handle"] == "asha" and sent["created_at"] == stamp(SLOT_1)
    assert conn.args_of("insert into messages") == (GID, USER, "On Saturday?", "Q10", FILM, NID)
    conn.finished()
    app, conn = app_for()
    async with client_for(app) as client:
        for extra in ({"film_id": "Q10"}, {"film": FILM}, {"film_id": "Q11", "film": FILM}):
            reply = await client.post(
                f"/v1/groups/{GID}/messages", json={"body": "x", **extra}, headers=HEADERS
            )
            assert reply.status_code == 422, extra
    conn.finished()


async def test_send_a_film():
    app, conn = app_for(
        ("from friendships where user_id", 1), ("insert into sent_films", "INSERT 0 1")
    )
    body = {"user_id": str(OTHER), "film_id": "Q10", "film": FILM, "note": None}
    async with client_for(app) as client:
        reply = await client.post("/v1/films/send", json=body, headers=HEADERS)
    assert (reply.status_code, reply.json()) == (201, {})
    assert conn.args_of("insert into sent_films") == (USER, OTHER, "Q10", FILM, None)
    app, conn = app_for(("from friendships where user_id", None))
    async with client_for(app) as client:
        assert (
            await client.post("/v1/films/send", json={**body, "note": "hi"}, headers=HEADERS)
        ).status_code == 404
    app, conn = app_for()
    async with client_for(app) as client:
        for bad in ({"user_id": str(USER)}, {"film_id": "Q11"}, {"note": "x" * 141}):
            assert (
                await client.post("/v1/films/send", json={**body, **bad}, headers=HEADERS)
            ).status_code == 422
    conn.finished()


WENT = [
    {"id": M_OWNER, "user_id": USER, "name": "Asha"},
    {"id": M_OTHER, "user_id": OTHER, "name": "Ravi, Jr."},
    {"id": M_GUEST, "user_id": None, "name": "Dad"},
]
EVENT = {"tz_offset_min": 330, "place": "PVR", "film_id": "Q10", "film": FILM, "starts_at": SLOT_1}
SET_NIGHT = ("for update", {**NIGHT_OF[1], "status": "set"})


async def test_wrapup_writes_one_stub_per_account_member_and_locks_each_user():
    app, conn = app_for(
        SET_NIGHT,
        ("from group_members m join groups g", OWNER_SEAT),
        ("from nights n join night_options f", EVENT),
        ("join night_rsvps r", WENT),
        ("pg_advisory_xact_lock", None),
        ("pg_advisory_xact_lock", None),
        ("insert into stubs", 1),
        ("insert into stubs", None),  # the second user deleted this stub earlier: it stays deleted
        ("update nights set status = 'done'", "UPDATE 1"),
        ("insert into messages", "INSERT 0 1"),
    )
    body = {"seat_row": "F", "first_seat": 7, "member_ids": None}
    async with client_for(app) as client:
        reply = await client.post(f"/v1/nights/{NID}/wrapup", json=body, headers=HEADERS)
    assert (reply.status_code, reply.json()) == (200, {"created": 1, "skipped": 1}), reply.text
    locks = [args for _, sql, args in conn.calls if "pg_advisory_xact_lock" in sql]
    assert locks == [(str(u),) for u in sorted([USER, OTHER], key=str)]  # a fixed order
    stubs = [args for _, sql, args in conn.calls if "insert into stubs" in sql]
    first, second = stubs
    assert (first[0], first[1], first[2], first[4]) == (USER, f"night-{NID}", "Q10", FILM)
    local = (SLOT_1 + timedelta(minutes=330)).date()
    assert first[3] == local and isinstance(first[3], date)
    data = first[5]
    assert (data["id"], data["no"], data["film"], data["date"], data["prec"]) == (
        f"night-{NID}",
        0,
        "Q10",
        local.isoformat(),
        "day",
    )
    assert (data["seat"], data["place"], data["with"]) == ("F7", "PVR", "Ravi Jr., Dad")
    assert data["created"].endswith("Z")
    assert second[0] == OTHER and second[5]["seat"] == "F8" and second[5]["with"] == "Asha, Dad"
    assert conn.args_of("insert into messages") == (
        GID,
        "wrapped",
        {"night_id": str(NID)},
        NID,
        None,
    )
    conn.finished()


async def test_wrapup_again_changes_no_status_and_names_members_when_asked():
    done = ("for update", {**NIGHT_OF[1], "status": "done"})
    app, conn = app_for(
        done,
        ("from group_members m join groups g", OWNER_SEAT),
        ("from nights n join night_options f", EVENT),
        ("join night_rsvps r", WENT[:2]),
        ("pg_advisory_xact_lock", None),
        ("pg_advisory_xact_lock", None),
        ("insert into stubs", None),
        ("insert into stubs", None),
    )
    async with client_for(app) as client:
        reply = await client.post(f"/v1/nights/{NID}/wrapup", json={}, headers=HEADERS)
    assert reply.json() == {"created": 0, "skipped": 2}
    conn.finished()
    app, conn = app_for(
        SET_NIGHT,
        ("from group_members m join groups g", OWNER_SEAT),
        ("from nights n join night_options f", EVENT),
        ("m.id = any($2::uuid[])", [WENT[1], WENT[2]]),
        ("pg_advisory_xact_lock", None),
        ("insert into stubs", 1),
        ("update nights set status = 'done'", "UPDATE 1"),
        ("insert into messages", "INSERT 0 1"),
    )
    body = {"seat_row": None, "first_seat": None, "member_ids": [str(M_OTHER), str(M_GUEST)]}
    async with client_for(app) as client:
        reply = await client.post(f"/v1/nights/{NID}/wrapup", json=body, headers=HEADERS)
    assert reply.json() == {"created": 1, "skipped": 0}
    assert conn.args_of("m.id = any($2::uuid[])") == (GID, [M_OTHER, M_GUEST])
    seat = conn.args_of("insert into stubs")[5]["seat"]
    assert re.fullmatch(r"[A-Z]([1-9]|1[0-9]|20)", seat)
    conn.finished()


async def test_wrapup_of_a_poll_and_by_a_stranger():
    app, conn = app_for(
        ("for update", NIGHT_OF[1]), ("from group_members m join groups g", OWNER_SEAT)
    )
    async with client_for(app) as client:
        reply = await client.post(f"/v1/nights/{NID}/wrapup", json={}, headers=HEADERS)
    assert reply.status_code == 409 and reply.json()["error"]["code"] == "not_set"
    other_host = {**NIGHT_OF[1], "status": "set", "host_id": OTHER}
    app, conn = app_for(
        ("for update", other_host), ("from group_members m join groups g", MEMBER_SEAT)
    )
    async with client_for(app) as client:
        assert (
            await client.post(f"/v1/nights/{NID}/wrapup", json={}, headers=HEADERS)
        ).status_code == 403
    app, conn = app_for(("for update", None))
    async with client_for(app) as client:
        assert (
            await client.post(f"/v1/nights/{NID}/wrapup", json={}, headers=HEADERS)
        ).status_code == 404
