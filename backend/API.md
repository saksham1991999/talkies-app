# Talkies API v1

Source of truth for the FastAPI backend (`backend/`) and the Flutter client (`lib/`). Change this file first, then both sides.

The app works without this API. The client hides every feature that needs it when the API is not configured, is down, or is not deployed.

## Conventions

- Base URL: the `TALKIES_API_URL` of the app build. JSON endpoints live under `/v1`. Two more routes: `/healthz` and `/j/{code}`.
- Auth: `Authorization: Bearer <access_token>`. Roles: **U** any signed-in user, **M** group member, **O** group owner, **H** night host or group owner.
- JSON: UTF-8, snake_case keys, at most 2 MB per request. Unknown request keys are rejected (422).
- Times: UTC ISO-8601 with milliseconds and `Z`, for example `2026-10-01T12:00:00.000Z`. The server rejects times without `Z`.
- Ids: lowercase uuid strings, except: `film_id` (`Q<digits>`, or `my:<device>.<n>` where noted), stub `id` (client text, at most 64 characters), and the integers `seq`, message `id`, and `cursor` of sync.
- Lists: `?limit` (1 to 100, default 30) and `?cursor`. Reply `{items, next_cursor}`. `next_cursor` is null at the end. A cursor is opaque.
- Film snapshot `film`: the compact film JSON of the app (`id, t, o, y, d, rt, dir, cast, g, l, c, ott, p, w, pop, k, sn`). The server treats it as opaque. At most 4 KB. A `file:` poster value is rejected.
- Error body: `{"error":{"code":"...","message":"...","detail":null}}`. `message` is English for developers. The app shows its own text.
- Status codes: 400 (`invalid_request`, or a code named below), 401 `unauthorized`, 403 `forbidden`, 404 `not_found` (also for blocked or invisible targets), 409 (code named below), 413 `too_large`, 422 `invalid_request` (input is never echoed), 429 `rate_limited` with `Retry-After`, 502 `upstream_unavailable`, 503 `db_unavailable`.
- Limits: group name 40, guest name 40 (unique per group, case-insensitive), display name 30, handle `^[a-z0-9_]{3,20}$` (stored lowercase), note 140, message 1000, report note 500, shared list 200 films, deck 120 films, swipes 50 per request, sync batch 200, 20 groups per user, 30 members per group, 20,000 stubs per user.

## Models

Every model has a snake_case name. `backend/tests/examples/<model>.<case>.json` holds exact wire JSON for it. The backend validates each file against its Pydantic model. The client test parses the same files. Every model needs an example and every example file needs a model.

```
card              {id, handle: str|null, display_name: str|null, avatar_color: 0..10}
session           {access_token, refresh_token, expires_at: int (epoch seconds), user: {id}}
health            {ok: bool, api: 1, auth: ["email"|"google"|"apple", ...]}
error             {error: {code, message, detail: any|null}}

otp_request       {email}
verify_request    {email, code}
refresh_request   {refresh_token}
id_token_request  {provider: "google"|"apple", id_token, access_token: str|null, nonce: str|null,
                   authorization_code: str|null (Apple only: buys the refresh token for grant revocation)}

me                {id, handle: str|null, display_name: str|null, avatar_color: int, visibility: "private"|"friends", share_ratings: bool}
me_patch          any of {handle, display_name, avatar_color, visibility, share_ratings}

sync_record       {kind: "stub"|"wish"|"meta"|"taste", id, updated_at, deleted: bool, film: film|null, data: object}
sync_record_seq   sync_record + {seq: int}
sync_push         {records: [sync_record]}
sync_push_result  {server_time, conflicts: [sync_record_seq], rejected: [{kind, id, code}]}
sync_pull         {server_time, records: [sync_record_seq], cursor: int, more: bool}

lookup            {card, relation: "none"|"friend"|"incoming"|"outgoing"}
friend_request_post    {user_id}
friend_request_result  {status: "pending"|"friends"}
friend_requests   {incoming: [card], outgoing: [card]}
match             {both: int, pct: int|null}
friend_list       {items: [{card, visible: bool, match: match|null}]}
profile_view      {card, relation: "self"|"friend", visible: bool, match: match|null,
                   stats: {films, viewings, avg_rating: float|null, top_genres: [str], top_langs: [str]}|null,
                   top_films: [{film_id, film, rating: float|null}], watchlist: [{film_id, film}]}
shelf             {items: [{film_id, film, rating: float|null, viewings: int}], next_cursor}
friends_who_watched  {items: [{user: card, rating: float|null}]}
feed              {items: [{id: str, kind: "watched"|"reaction"|"sent", user: card, film_id, film,
                            rating: float|null, reaction: int|null, note: str|null, my_reaction: int|null}], next_cursor}
reaction_put      {user_id, film_id, reaction: 0..7|null}
block_post        {user_id}
block_list        {items: [card]}
report_post       {kind: "user"|"message"|"group", target_id: str, reason: "spam"|"abuse"|"harassment"|"inappropriate"|"other", note: str|null}
report_result     {id}

member            {id, name, avatar_color: int, handle: str|null, guest: bool, owner: bool, me: bool}
group             {id, name, invite_code, deck_version: int, member_count: int}
group_list        {items: [group]}
group_detail      group + {members: [member]}
group_create      {name}
group_patch       {name}
invite_code       {invite_code}
join_post         {code}
guest_post        {name}
group_films       {items: [{film_id, film}]}
group_film_put    {film}
deck              {version: int, items: [{film_id, film, seen_by: int}]}
deck_put          {base_version: int, items: [{film_id, film}]}
deck_put_result   {version: int}
deck_inputs       {tastes: [object], seen: [film_id], wanted: [{film_id, film, n: int}]}
swipes_put        {swipes: [{film_id, vote: "want"|"skip"|"seen", member_id: uuid|null}]}
swipes_result     {saved: int}
tallies           {tallies: {film_id: {want, skip, seen}}, mine: {film_id: vote}}

night             {id, group_id, status: "poll"|"set"|"done", host_id: uuid|null, tz_offset_min: int, place: str|null,
                   options: [{id, kind: "film"|"slot", position: int, film_id: str|null, film: film|null, starts_at: time|null, approvals: int}],
                   mine: [option id], event: {film_id, film, starts_at, tz_offset_min, place}|null,
                   rsvps: [{member_id, response: "yes"|"no"|"maybe"}]}
night_list        {items: [night]}
night_create      {films: [{film_id, film}], slots: [time], tz_offset_min: int, place: str|null}
votes_put         {option_ids: [uuid], member_id: uuid|null}
votes_result      {approvals: {option_id: int}}
close_post        {film_option_id: uuid|null, slot_option_id: uuid|null, place: str|null}
rsvp_put          {response: "yes"|"no"|"maybe", member_id: uuid|null}

message           {id: int, kind: "text"|"system", sender: card|null, body: str|null, code: str|null, args: object|null,
                   film_id: str|null, film: film|null, night_id: uuid|null, created_at: time}
message_list      {items: [message], has_more: bool}
message_post      {body: str (1..1000), film_id: str|null, film: film|null, night_id: uuid|null}
wrapup_post       {seat_row: str|null ("A".."Z"), first_seat: int|null (1..99), member_ids: [uuid]|null}
wrapup_result     {created: int, skipped: int}
send_film         {user_id, film_id, film, note: str|null}
```

`match.pct` is null when the two shelves share no film. `friend_list.items[].match` is null when the friend's profile is not shared with friends.

## Endpoints

### Phase 1: login, sync, privacy, delete

| Method and path | Auth | Request | Reply | Errors |
|---|---|---|---|---|
| `GET /healthz` | none | | `health` (503 with `ok:false` and `auth:[]` when the database is down; cache the database check for 5 s) | |
| `POST /v1/auth/otp` | none | `otp_request` | 204 | 400, 429, 502 |
| `POST /v1/auth/verify` | none | `verify_request` | `session` | 400 `otp_invalid`, 429, 502 |
| `POST /v1/auth/refresh` | none | `refresh_request` | `session` (60 per 5 min per IP) | 400 `refresh_invalid`, 429, 502 |
| `POST /v1/auth/id-token` | none | `id_token_request` | `session` | 400 `id_token_invalid`, 404 `provider_disabled`, 502 |
| `POST /v1/auth/logout` | U | | 204 | |
| `GET /v1/me` | U | | `me` (creates the profile on first call) | 401 `account_deleted` |
| `PATCH /v1/me` | U | `me_patch` | `me` | 409 `handle_taken` |
| `DELETE /v1/me` | U | | 204 | 502 |
| `POST /v1/sync/push` | U | `sync_push` | `sync_push_result` | 413 |
| `GET /v1/sync/pull?after=0&limit=200` | U | | `sync_pull` | |

Auth proxy: the server forwards to Supabase Auth and whitelists the body fields. `otp` forces `create_user: true`. `verify` forces `type: "email"`. `id-token` forwards `provider`, `id_token`, `access_token`, `nonce`. An `apple` call with `authorization_code` also trades that code for an Apple refresh token and keeps it, so `DELETE /v1/me` can revoke the grant; a failure there never fails the sign-in. `expires_at` is computed when Supabase omits it.

`GET /v1/me` creates the profile row with `visibility: "private"`, `share_ratings: false`, `avatar_color` from the user id.

`DELETE /v1/me` deletes the Supabase user FIRST (with the service key; a 404 counts as done), then runs `delete_account`. Until the second half runs, every surviving access token gets 401 `account_deleted` from every route, so a crash in between cannot resurrect the profile and cannot be exploited; repeating `DELETE /v1/me` finishes the job.

Sync:
- `data` by kind:
  - `stub`: the app's `Stub.toJson()`. `film` is the wire film id. `priv: true` marks a private stub. `id` of the record is the stub id.
  - `wish`: `Wish.toJson()`. The record `id` is the wire film id.
  - `meta`: `{tags: [str], venues: [{name, type}], hidden: [film_id]}`. The record `id` is `meta`.
  - `taste`: an object defined by the app (`{"v":1,...}`), at most 24 KB. The record `id` is `taste`.
- Wire film ids: `Q<digits>`, or `my:<device>.<n>` for a custom film (`^my:[A-Za-z0-9_.-]{1,40}$`). The record-level `film` holds the snapshot.
- A tombstone has `deleted: true`, `film: null`, `data: {}`.
- The server derives columns from a stub: `film_id` from `data.film`, `rating` from `data.rating` (0.1 to 5.0), `private` from `data.priv == true`, `watched_on` from `data.date` when `data.prec == "day"`. `watched_on` only orders results and decides feed freshness. No response carries it.
- Last write wins by `updated_at`. The server clamps it to now + 5 minutes. Incoming wins only if it is strictly newer. A tie keeps the server row. `conflicts` lists the server rows that kept their place. A record in neither `conflicts` nor `rejected` was accepted. `rejected.code`: `invalid_record`, `too_large`, `limit_reached`.
- Pull returns the caller's rows with `seq > after`, ascending, at most `limit`. `cursor` is the largest `seq` returned, or `after` if none. `more` is true when rows remain. Push and delete take `pg_advisory_xact_lock` on the user, so `seq` order matches commit order.

### Phase 2: friends, profiles, feed, report, block

| Method and path | Auth | Request | Reply | Errors |
|---|---|---|---|---|
| `GET /v1/users/lookup?handle=` | U | | `lookup` (exact handle, 30 per hour) | 404, 429 |
| `POST /v1/friends/requests` | U | `friend_request_post` | `friend_request_result` (a mutual request accepts) | 404, 409 `already_pending`, 429 |
| `GET /v1/friends/requests` | U | | `friend_requests` | |
| `POST /v1/friends/requests/{uid}/accept` | U | | 204 | 404 |
| `DELETE /v1/friends/requests/{uid}` | U | | 204 (decline or cancel) | 404 |
| `GET /v1/friends` | U | | `friend_list` (at most 500, ordered by name) | |
| `DELETE /v1/friends/{uid}` | U | | 204 | |
| `GET /v1/users/{uid}` | U | | `profile_view` (`uid` may be the caller: `relation: "self"`, shown as friends see it) | 404 unless friend or self |
| `GET /v1/users/{uid}/films` | U | | `shelf` | 404 |
| `GET /v1/films/{film_id}/friends` | U | | `friends_who_watched` | 422 for a custom film |
| `GET /v1/feed` | U | | `feed` | 400 `bad_cursor` |
| `PUT /v1/reactions` | U | `reaction_put` | 204 (null clears) | 404 |
| `GET /v1/blocks` | U | | `block_list` | |
| `POST /v1/blocks` | U | `block_post` | 204 (also deletes the friendship, requests, reactions, and sent films between the pair) | 404 |
| `DELETE /v1/blocks/{uid}` | U | | 204 | |
| `POST /v1/reports` | U | `report_post` | `report_result` (stores a snapshot of a reported message) | 404, 429 |

Rules:
- Another person's content is visible only if the owner's `visibility` is `friends`, the two are friends, and neither blocked the other. Otherwise 404 (profile, shelf) or `visible: false` (friend list).
- Another person's stubs come from views without the `data` column: not deleted, not private, QID only. `rating` is null unless the owner's `share_ratings` is true.
- No response to another person holds a diary date, `created`, `memo`, `place`, `seat`, `price`, `with`, `tags`, `no`, `planned`, or `added`. `stats` has no per-month or per-year numbers.
- `profile_view.top_films`: at most 10, highest rating first when ratings are shared, else most viewings; ties by most recent watch (ordering only). `watchlist`: at most 50, QID only. `top_genres` and `top_langs`: at most 3.
- `feed`: union of friends' public stubs, reactions to the caller's stubs, and films sent to the caller, minus blocked users. Order by `feed_seq` descending. A stub gets a `feed_seq` only when it is public and fresh (day precision, dated within 14 days of today), so an import never floods a feed. An edit keeps it, and the 14-day window is re-checked on every read, so a stale entry un-shares from the feed without a new push. `feed.items[].id` is `<w|r|s>:<feed_seq>`. The cursor is the last `feed_seq`, base64url, unsigned. `my_reaction` is set on `watched` items.
- `shelf`: most recently watched first (ordering column never returned), ties by film id. The cursor is an offset.
- Reaction numbers 0 to 7 map to a fixed emoji set in the app.
- Match: see `backend/app/logic/match.py`. `both` counts the viewer's own films (private included) that also appear in the friend's public films. A friend who hides ratings never contributes ratings.
- Report `kind` and `target_id`: `user` and `group` take a uuid, `message` takes the message id as a string. A `user` report needs a relationship: the target must be a friend or share a group with the reporter (404 otherwise, so the endpoint cannot probe arbitrary ids). When an account is deleted, its reports move to an internal `reports_archive` table (kind, target id, reason, note, date), so the moderation trail survives without keeping any user id.

### Phase 3: groups, shared list, deck, swipes

| Method and path | Auth | Request | Reply | Errors |
|---|---|---|---|---|
| `GET /j/{code}` | none | | HTML landing page (no database call) | 404 for a malformed code |
| `POST /v1/groups` | U | `group_create` | 201 `group` (the caller becomes owner and member) | 409 `group_limit` |
| `GET /v1/groups` | U | | `group_list` | |
| `GET /v1/groups/{gid}` | M | | `group_detail` | 404 |
| `PATCH /v1/groups/{gid}` | O | `group_patch` | `group` | 403 |
| `DELETE /v1/groups/{gid}` | O | | 204 | 403 |
| `POST /v1/groups/{gid}/invite/rotate` | O | | `invite_code` | 403 |
| `POST /v1/groups/join` | U | `join_post` | `group` (idempotent for a member) | 404 `invalid_code`, 409 `group_full`, 429 |
| `DELETE /v1/groups/{gid}/members/{mid}` | M, O for others | | 204 (`mid` is a member id or `me`) | 403 |
| `POST /v1/groups/{gid}/guests` | O | `guest_post` | 201 `member` | 409 `name_taken` |
| `GET /v1/groups/{gid}/films` | M | | `group_films` | |
| `PUT /v1/groups/{gid}/films/{film_id}` | M | `group_film_put` | 204 (idempotent) | 409 `list_full`, 422 for a custom film |
| `DELETE /v1/groups/{gid}/films/{film_id}` | M | | 204 | |
| `GET /v1/groups/{gid}/deck` | M | | `deck` | |
| `PUT /v1/groups/{gid}/deck` | M | `deck_put` | `deck_put_result` | 409 `deck_conflict` with `detail: {current_version}`, 429 |
| `GET /v1/groups/{gid}/deck-inputs` | M | | `deck_inputs` | |
| `PUT /v1/groups/{gid}/swipes` | M | `swipes_put` | `swipes_result` | 403 |
| `GET /v1/groups/{gid}/tallies?member_id=` | M | | `tallies` (`mine` is for `member_id`, default the caller) | |

Rules:
- Invite code: 8 characters from `A-HJ-KM-NP-Z2-9`, unique. All members see it. `GET /j/{code}` names no group, sends `noindex` and `no-referrer`, and shows the code, an "Open in Talkies" link to `talkies://join?code=CODE`, and the store links.
- Members are users or guests (`user_id` null). Only the owner writes swipes, votes, and RSVPs for a guest (`member_id`). Anyone else sending another `member_id` gets 403.
- Deck: one per group. A member uploads a built deck with the `base_version` they read. A stale version gets 409 and adopts the winner. Limit: one write per 10 seconds per member per group, so one member cannot starve the rest. `seen_by` counts members by the Seen rule below.
- `deck_inputs`: `tastes` are the members' taste documents (users only, including the caller). `wanted` is every member's watchlist (non-deleted, QID only) plus the shared list, with `n` = how many sources want the film. `seen` follows the Seen rule. Nothing names a member.
- **Seen rule**: a film is seen if (a) it is in the viewer's own stubs, (b) it is in a stub the viewer could already see on that member's profile (friend, profile shared, not private), or (c) any member swiped `seen` on it. Never per member.
- Blocked members stay in a group, but the blocker does not see them: their swipes do not count in `tallies` or `seen_by`, and their messages (text and system messages about them) are hidden. Their own view is unchanged.
- `tallies` counts all swipes per film and vote across members, guests included.
- A member who leaves loses their swipes and votes. If the owner leaves, ownership moves to the earliest-joined linked member. With none left, the group is deleted.

### Phase 4: nights

| Method and path | Auth | Request | Reply | Errors |
|---|---|---|---|---|
| `POST /v1/groups/{gid}/nights` | M | `night_create` (1 to 3 films, 1 to 2 slots) | 201 `night` | 422 |
| `GET /v1/groups/{gid}/nights` | M | | `night_list` (at most 50, newest first) | |
| `GET /v1/nights/{nid}?member_id=` | M | | `night` (`mine` is for `member_id`, default the caller) | 404 |
| `DELETE /v1/nights/{nid}` | H | | 204 | 403 |
| `PUT /v1/nights/{nid}/votes` | M | `votes_put` (replaces the member's votes) | `votes_result` | 403, 409 `not_polling` |
| `POST /v1/nights/{nid}/close` | H | `close_post` | `night` (status `set`) | 403, 409 `not_polling` |
| `PUT /v1/nights/{nid}/rsvp` | M | `rsvp_put` | 204 | 403, 409 `not_set` |

Rules:
- Exactly 1 film and 1 slot: the night is created as `set` with its event. Otherwise `poll`. Both post a `system` message.
- Approval voting: a member approves any options. Close without ids: the film and slot with the most approvals win, ties by lowest `position`.
- Slots must fall between now minus 1 day and now plus 400 days.
- `rsvps` lists only members who replied.

### Phase 5: chat, wrap-up, send a film

| Method and path | Auth | Request | Reply | Errors |
|---|---|---|---|---|
| `GET /v1/groups/{gid}/messages?after=&before=&limit=` | M | | `message_list` (ascending; no ids = the latest page) | |
| `POST /v1/groups/{gid}/messages` | M | `message_post` | 201 `message` | 429 |
| `POST /v1/nights/{nid}/wrapup` | H | `wrapup_post` | `wrapup_result` | 403, 409 `not_set` |
| `POST /v1/films/send` | U | `send_film` | 201 `{}` | 404, 422, 429 |

Rules:
- `system` messages carry `code` and `args`, so the app writes the text in its own language: `joined {name}`, `left {name}`, `poll_open {night_id}`, `night_set {night_id, film_id, starts_at}`, `wrapped {night_id}`.
- A blocked user's messages are hidden from the blocker and the reverse.
- Wrap-up inserts one stub per account member into their diary: `id` is `night-<night_id>`, `ON CONFLICT DO NOTHING` (a stub the user deleted stays deleted), `no: 0` (the phone assigns the ticket number), the night's film, `date` from `starts_at + tz_offset_min`, `prec: "day"`, `place` from the night, `seat` = `<row><first_seat + i>` with one random row letter and seats in member order, `with` = the other attendees' names joined by commas (commas removed from names). Default members: RSVP `yes`. Guests get no stub. The night becomes `done`. Takes the advisory lock of each user it writes for.
- `send_film` needs a friendship and no block. The film appears in the receiver's feed as `sent`.

## Privacy checklist for implementers

1. New profiles are private. No other user sees any content until `visibility` is `friends`.
2. A private stub never leaves its owner: not in a shelf, stats, top films, feed, match, `friends_who_watched`, or `seen`.
3. No date of a diary entry reaches another person. The test seeds canary dates and memo text, calls every route as a non-owner, and asserts the canaries are absent.
4. A blocked user is invisible in both directions, everywhere.
5. Every table has RLS on with no policy, and no grant to `anon` or `authenticated`.
6. Account deletion leaves no row that points to the user.
