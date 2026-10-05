-- Phase 2: friends, reactions, blocks, reports, and the views that other
-- people read through.
--
-- Non-owner reads use only these views. None has a `data` column or a diary
-- timestamp. The one date-like column is `recency` (a rank, 1 = newest): it
-- exists only for ORDER BY and no response returns it.

-- Header: new objects get no grant for the public API roles.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges revoke execute on functions from public;

-- Pending requests. An accepted request becomes two friendships rows.
create table friend_requests (
  from_id uuid not null references profiles (id) on delete cascade,
  to_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_id, to_id),
  constraint friend_requests_not_self check (from_id <> to_id)
);
create index friend_requests_to on friend_requests (to_id);

-- Accepted friendships, one row per direction.
create table friendships (
  user_id uuid not null references profiles (id) on delete cascade,
  friend_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  constraint friendships_not_self check (user_id <> friend_id)
);
create index friendships_friend on friendships (friend_id);

create table blocks (
  blocker_id uuid not null references profiles (id) on delete cascade,
  blocked_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);
create index blocks_blocked on blocks (blocked_id);

-- An emoji reaction (0 to 7) of `user_id` to a public stub of `target_id`.
-- `film` is a copy of the snapshot, so the feed needs no read of the stub.
-- A new reaction takes a new feed_seq, so it moves to the top of the feed.
create table reactions (
  user_id uuid not null references profiles (id) on delete cascade,
  target_id uuid not null references profiles (id) on delete cascade,
  film_id text not null,
  film jsonb not null,
  reaction smallint not null,
  feed_seq bigint not null default nextval('public.feed_seq'),
  primary key (user_id, target_id, film_id),
  constraint reactions_range check (reaction between 0 and 7),
  constraint reactions_film_id check (film_id ~ '^Q[0-9]{1,12}$'),
  constraint reactions_not_self check (user_id <> target_id),
  constraint reactions_film_size check (octet_length(film::text) <= 5120)
);
create index reactions_target_seq on reactions (target_id, feed_seq desc);

-- A report. `target_user_id` is the reported user (or the sender of a reported
-- message). It cascades, so deleting an account also removes reports about it.
-- `snapshot` keeps the text of a reported message. No response returns it.
create table reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles (id) on delete cascade,
  target_user_id uuid references profiles (id) on delete cascade,
  kind text not null,
  target_id text not null,
  reason text not null,
  note text,
  snapshot jsonb,
  created_at timestamptz not null default now(),
  constraint reports_kind_values check (kind in ('user', 'message', 'group')),
  constraint reports_reason_values check (reason in ('spam', 'abuse', 'harassment', 'inappropriate', 'other')),
  constraint reports_note_len check (char_length(note) <= 500),
  constraint reports_target_len check (char_length(target_id) between 1 and 64),
  constraint reports_snapshot_size check (octet_length(snapshot::text) <= 8192)
);
create index reports_reporter on reports (reporter_id);
create index reports_target_user on reports (target_user_id);

-- Reports cascade away when a reported user (or reporter) deletes their
-- account. The moderation trail must survive, without keeping any uuid or
-- message text that points at a person. A before-delete trigger copies the
-- minimal fields into `reports_archive`. No role may read it from the API.
create table reports_archive (
  id uuid primary key,  -- the report's own id, not a user's
  kind text not null,
  -- Null for a report about a user: their account id must not survive the
  -- deletion. Message and group ids stay, so the trail keeps its context.
  target_id text,
  reason text not null,
  note text,
  reported_at timestamptz not null
);

create function archive_report() returns trigger
language plpgsql
as $$
begin
  insert into reports_archive (id, kind, target_id, reason, note, reported_at)
  values (old.id, old.kind,
          case when old.kind = 'user' then null else old.target_id end,
          old.reason, old.note, old.created_at)
  on conflict (id) do nothing;
  return old;
end
$$;

create trigger reports_archive before delete on reports
  for each row execute function archive_report();

create function blocked_either(a uuid, b uuid) returns boolean
language sql
stable
as $$
  select exists (
    select 1 from blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  )
$$;

-- Who may look at whose shared profile: (viewer, owner) pairs. A friend counts
-- when the owner shares with friends and nobody blocked anybody. Every user
-- also appears as their own audience, so "my profile as friends see it" uses
-- the same views. Queries for feeds and friend lists must add owner <> viewer.
create view v_audience with (security_invoker = true) as
  select f.user_id as viewer_id, f.friend_id as owner_id
  from friendships f
  join profiles p on p.id = f.friend_id
  where p.visibility = 'friends'
    and not blocked_either(f.user_id, f.friend_id)
  union all
  select id, id from profiles;

-- Stubs another person may see: not deleted, not private, QID films only,
-- rating null unless the owner shares ratings. `recency` ranks the owner's
-- visible stubs, newest first (ordering only, never returned).
create view v_visible_stubs with (security_invoker = true) as
  select a.viewer_id,
         s.user_id as owner_id,
         s.film_id,
         s.film,
         case when p.share_ratings then s.rating end as rating,
         s.feed_seq,
         s.recency
  from (
    -- Freshness is re-checked on every read, not latched at push time: a stub
    -- whose feed_seq was granted at push loses it here once its watched_on is
    -- more than 14 days old (backend/app/logic/validate.py FEED_FRESH_DAYS = 14,
    -- keep the two in step). The stub itself stays visible on the profile.
    select t.user_id, t.film_id, t.film, t.rating,
           case when t.watched_on >= current_date - 14 then t.feed_seq end as feed_seq,
           row_number() over (
             partition by t.user_id
             order by t.watched_on desc nulls last, t.seq desc
           ) as recency
    from stubs t
    where t.deleted_at is null
      and not t.private
      and t.film_id ~ '^Q[0-9]{1,12}$'
  ) s
  join profiles p on p.id = s.user_id
  join v_audience a on a.owner_id = s.user_id;

-- Watchlist entries another person may see. `ord` orders by last change.
create view v_visible_wishes with (security_invoker = true) as
  select a.viewer_id,
         w.user_id as owner_id,
         w.film_id,
         w.film,
         w.seq as ord
  from wishes w
  join v_audience a on a.owner_id = w.user_id
  where w.deleted_at is null
    and w.film_id ~ '^Q[0-9]{1,12}$';

-- The caller's own films, private ones included, QID only, no data column.
-- Always filter by the caller's id. Never use it for another user.
create view v_my_stubs with (security_invoker = true) as
  select user_id, film_id, rating, private
  from stubs
  where deleted_at is null
    and film_id ~ '^Q[0-9]{1,12}$';

-- Footer: RLS on with no policy, and no access for the public API roles.
alter table friend_requests enable row level security;
alter table friendships enable row level security;
alter table blocks enable row level security;
alter table reactions enable row level security;
alter table reports enable row level security;
alter table reports_archive enable row level security;

revoke all on table friend_requests, friendships, blocks, reactions, reports, reports_archive
  from anon, authenticated;
revoke all on function archive_report() from public, anon, authenticated;
revoke all on table v_audience, v_visible_stubs, v_visible_wishes, v_my_stubs from anon, authenticated;
revoke all on function blocked_either(uuid, uuid) from public, anon, authenticated;
