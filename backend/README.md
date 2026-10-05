# Talkies backend

The backend of "Talkies with friends". It is a FastAPI app. Supabase Auth signs people in and Supabase Postgres stores the data.

The Flutter app talks only to this server. It never talks to Supabase. The app works without this server. It hides every online feature when the server is not set up or is down.

`API.md` is the contract between this server and the app. Change `API.md` first, then the code.

## What is here

| Path | Content |
|---|---|
| `app/` | The server. `routers/` holds the routes with their SQL. `logic/` holds pure functions. `schemas/` holds the Pydantic models of `API.md`. |
| `tests/pure/` | Tests that need no database. |
| `tests/db/` | Tests that need Postgres. They skip when `TEST_DATABASE_URL` is not set. |
| `tests/examples/` | One JSON file per model and case. The Flutter tests read the same files. |
| `../supabase/migrations/` | Five SQL files, one per phase. |
| `../supabase/config.toml`, `../supabase/templates/otp.html` | Auth settings and the sign-in email. |

## Environment variables

Copy `.env.example` to `.env` for local runs. On a host, set real environment variables.

| Name | Meaning |
|---|---|
| `SUPABASE_URL` | Project URL, for example `https://abc.supabase.co`. |
| `SUPABASE_ANON_KEY` | Used for sign-in calls. Stays on the server. |
| `SUPABASE_SERVICE_ROLE_KEY` | Used to delete a user. Stays on the server. |
| `SUPABASE_JWT_SECRET` | Optional. Only for a project that still signs tokens with the shared HS256 secret. |
| `DATABASE_URL` | The transaction pooler string. A `?pgbouncer=true` suffix is removed. |
| `PUBLIC_BASE_URL` | The public address of this server. It goes into link previews of invite links. |
| `AUTH_PROVIDERS` | Comma list of sign-in methods: `email`, `google`, `apple`. Default `email`. |
| `APPLE_CLIENT_ID` | The Apple client ID, which is the app bundle ID. With the secret, turns on Apple grant revocation. |
| `APPLE_CLIENT_SECRET` | The ES256 client-secret JWT minted from the Apple team key. |
| `DB_POOL_MAX` | Most database connections in this process. Default 10. |

The server starts with none of these set. Sign-in routes answer 502 while Supabase is not set up. Other routes answer 401 without a valid token and 503 while the database is not set or not reachable. `GET /healthz` answers 503 while the database is not reachable.

## Run it on your computer

1. Install dependencies.

   ```sh
   cd backend
   uv sync
   ```

2. Create `.env` from `.env.example` and fill it in.
3. Start a database and apply the migrations. For a local Supabase:

   ```sh
   supabase start
   supabase db reset
   ```

4. Start the server.

   ```sh
   uv run uvicorn app.main:app --reload
   ```

5. Check it.

   ```sh
   curl http://localhost:8000/healthz
   ```

   The reply is `{"ok":true,"api":1,"auth":["email"]}`.

6. Build the app with the address of the server. The address must be HTTPS: the app refuses an `http://` one (`_uri()` in `lib/net/api.dart`). Uvicorn in step 4 serves plain HTTP, so put a TLS proxy in front of it and point the app at that proxy: `flutter run --dart-define=TALKIES_API_URL=https://<your host>` (an Android emulator reaches the host as `10.0.2.2`, an iOS simulator as `localhost`). For a scratch build only, relax the HTTPS check and use the plain address instead: `--dart-define=TALKIES_API_URL=http://10.0.2.2:8000` or `http://localhost:8000`.

## Set up Supabase

1. Create a Supabase project. Copy the project URL, the anon key, and the service role key.
2. Link the folder and apply the migrations:

   ```sh
   supabase link --project-ref <ref>
   supabase db push
   ```

   Apply all five migrations. The routes of every phase use tables from all five.

3. Set up sign-in in the dashboard, under Authentication:
   - **Email code.** The sign-in email must show the code. Put `{{ .Token }}` in both the Magic Link template and the Confirm signup template. `supabase/config.toml` and `supabase/templates/otp.html` already do this for a local stack, and `supabase config push` sends them to a linked project. In the dashboard, paste the body of `supabase/templates/otp.html` into both templates.
   - **Custom SMTP.** The built-in mailer sends very few emails and is meant for tests. Set your own SMTP server under SMTP Settings.
   - **Anonymous sign-ins.** Keep them off.
   - **Passwords.** The app has no password screen and the server calls no password endpoint. Keep the anon key on the server only. Never put it in the app.
   - **Google.** Turn the provider on. Add the web and iOS client IDs to the authorized client IDs. Turn on "Skip nonce checks" for the iOS client, because the Google iOS SDK does not give the app the raw nonce.
   - **Apple.** Turn the provider on. Use the app bundle ID as the client ID. The app sends the raw nonce and Supabase checks its hash inside the Apple token. Set `APPLE_CLIENT_ID` (the bundle ID) and `APPLE_CLIENT_SECRET` (the ES256 client-secret JWT minted from the Apple team key) on the backend too. With both set, the server exchanges the authorization code of an Apple sign-in for a refresh token and stores it on the profile, so `DELETE /v1/me` can revoke the grant (App Store rule 4.8). Without them, or when the exchange fails, the sign-in and the deletion still work and the revoke is skipped with a log line.
4. Database user. Use the pooler string of the `postgres` user. That user owns the tables, so RLS (which has no policy) does not hide rows from it. Any other role would see no rows.
5. Set `AUTH_PROVIDERS` to the methods you switched on, for example `email,google,apple`. `GET /healthz` lists them and the app shows only those.
6. Token keys. A new project signs tokens with asymmetric keys. The server reads the public keys from `<SUPABASE_URL>/auth/v1/.well-known/jwks.json`. Set `SUPABASE_JWT_SECRET` only if the project still uses the shared secret.

## Deploy the container

```sh
docker build -t talkies-api backend
docker run -p 8000:8000 --env-file backend/.env talkies-api
```

The image runs `uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'`.

1. Put the container behind a proxy that ends TLS and sets `X-Forwarded-For` itself. The rate limiter reads the client IP from that header. Without `--proxy-headers` (or when running uvicorn any other way), every client looks like the proxy and shares one limit, so requests that still carry `X-Forwarded-For` from a non-trusted address are refused with 429 and an error is logged: the limiter fails closed rather than grouping everyone into one bucket.
2. Never expose the container to the internet without that proxy. With `--forwarded-allow-ips='*'`, any client could set `X-Forwarded-For` and pick its own IP.
3. Run one instance. The rate limiter keeps its counts in the memory of one process.
4. Use `GET /healthz` as the health check. It answers 200 when the database works and 503 when it does not. The database check is cached for 5 seconds.
5. Build the app with `--dart-define=TALKIES_API_URL=https://<your host>`. Publish the privacy page and the store text in the same release.

## Check the code

```sh
uv run ruff check .
uv run ruff format --check .
uv run pytest -q
uv run python -c "from app.main import app; app.openapi()"
```

The database tests run against a real Postgres. Locally they are skipped without `TEST_DATABASE_URL`; CI (`.github/workflows/ci.yml`) always runs them against a Postgres service container. Create an empty database whose name contains `test`, then:

```sh
TEST_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/talkies_test uv run pytest tests/db
```

The tests drop and rebuild the `public` and `auth` schemas of that database. They add a small stand-in for Supabase (`tests/db/00_supabase_stub.sql`) and apply every migration. The connection has to be a superuser, not just the owner of the tables: the stand-in creates the `anon`, `authenticated` and `service_role` roles, and one deletion test builds the half-deleted window with `set session_replication_role = replica`, which is superuser-only. The `postgres` user of the `postgres:17` service container in CI is one.

What the checks cover:

- `tests/pure/test_contract.py`: `API.md`, the Pydantic models, and `tests/examples` agree.
- `tests/pure/test_sql.py`: a Postgres parser reads every migration and every SQL string of the app. It checks table and column names, parameter counts, RLS on every table, no policies, cascading foreign keys, and that SQL for another person never reads `data` or an owner table.
- `tests/pure/test_routes_*.py`: each route runs against a scripted database. They check the order of calls, the arguments, and the reply shape.
- `tests/pure/test_jwt.py`, `test_gotrue.py`, `test_logic.py`, `test_boot.py`: tokens, the Supabase proxy, pure logic, and start-up without a database.
- `tests/db/`: sync races and last-write-wins, the privacy canary test, access by the `anon` role, deletion of every row, deck conflicts, guests, group limits, wrap-up, and chat.

## How it protects data

- The server is the only reader. Every table has RLS on, no policy, and no grant for `anon` or `authenticated`.
- Another person's films come only from the views `v_visible_stubs` and `v_visible_wishes`. They have no `data` column, no timestamp, and no private stub. Ratings are null unless the owner shares them.
- Film snapshots are cut down to the known keys when they arrive, so a snapshot cannot carry diary text.
- A new profile is private. Friends see nothing until the owner chooses "friends".
- A blocked user disappears for both people: lookup, profile, feed, roster, and chat.
- `DELETE /v1/me` runs `delete_account`, which deletes the profile. Every table cascades from it. Groups that the user owns pass to the earliest member, or go when nobody else is in them. Before a report row goes, `archive_report()` copies its kind, target id (null for a report about a user), reason, note and date to `reports_archive`, which carries no name, email, account id or message text. The server then deletes the Supabase user.
- Logs hold no request bodies, no emails, and no codes.

## Limits

| Limit | Value |
|---|---|
| Request body | 2 MB |
| Sync batch | 200 records |
| Stubs per user, and wishes per user | 20,000 |
| Film snapshot | 4 KB |
| Taste document | 24 KB |
| Groups per user | 20 |
| Members per group, guests included | 30 |
| Shared list | 200 films |
| Deck | 120 films |
| Swipes per request | 50 |
| Sign-in code request | 30 per hour per IP, 10 per hour per email |
| Code check | 30 per hour per IP |
| Handle lookup | 30 per hour per user |
| Join with code | 10 per hour per user |
| Friend requests | 30 per hour per user |
| Messages | 30 per minute per user |
| Sent films | 30 per hour per user |
| Reports | 20 per hour per user |
| Deck writes | 1 per 10 seconds per member per group |

## Where `API.md` is silent

The code makes these choices:

- The limits for friend requests, messages, sent films, and reports, and the per-email limit for sign-in codes, are the values in the table above.
- A wish limit of 20,000 per user, next to the stub limit.
- `night.host_id` is the user id of the host. It is null when the host deleted the account.
- `POST /v1/nights/{nid}/wrapup` also works on a night that is already `done`. It adds nothing then and answers `created: 0`. A poll answers 409 `not_set`.
- `GET /v1/users/{uid}/films` answers 404 for your own id. The app builds your own shelf from the diary on the phone.
- `GET /v1/users/{uid}` for your own id returns the profile as friends would see it, also when your profile is private (`visible` is false then).
- A system message about a person (`joined`, `left`) is deleted with that person's account. The table `messages` has a `subject_id` column for this. No response shows it.
- The size limits in the migrations are about 25 percent above the limits in the code. The code limit is the exact one.
- `GET /j/{code}` loads the Tanker font from Fontshare and sends `Referrer-Policy: no-referrer`, so the code does not leave in a referrer.

## Known gaps

- Apple revocation covers the sign-ins that happened while `APPLE_CLIENT_ID` and `APPLE_CLIENT_SECRET` were set. An account that signed in with Apple before them stored no refresh token, so deleting it logs the skip and cannot revoke that grant. The person can still stop the app in the Apple ID settings.
- Supabase backups can hold data for some time after an account is deleted.
- The rate limiter is per process.
- A token key that Supabase revokes stays trusted until the server fetches the key list again. That happens when a token with an unknown key id arrives, at most once per minute. Tokens last one hour.
- The wrap-up writes the other guests' names into "who you went with", also for two people who blocked each other.
- Chat is polling. There is no WebSocket.
- The SQL was never run against a database while this was written. The parser checks, the scripted route tests, and the database tests in `tests/db` are the safety net. Expect first-run defects and run `tests/db` first.
