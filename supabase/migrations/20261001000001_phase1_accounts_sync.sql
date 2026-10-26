-- Phase 1: profiles and sync.
--
-- Rules for every migration in this folder:
--   1. Only the backend reads or writes these tables. The Supabase public API
--      (anon, authenticated) gets no grant, and RLS is on with no policy.
--   2. A table that points at a user cascades from `profiles`, so deleting a
--      profile removes every row of that user.
--   3. jsonb size limits use octet_length of the text cast. The app enforces
--      the exact caps. These checks are a backstop with about 25 percent slack,
--      because jsonb text is not byte-identical to the client JSON.

-- Header: new objects get no grant for the public API roles.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges revoke execute on functions from public;

-- Sync order: one counter for stubs, wishes and user_docs. A trigger fills
-- `seq` on every insert or update. Push and delete take pg_advisory_xact_lock
-- on the user, so for one user the seq order is the commit order.
create sequence sync_seq;

-- Feed order. Stubs, reactions, and sent films share this counter, so a feed
-- id like `w:812` is unique. It carries recency without any date.
create sequence feed_seq;

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text,
  display_name text,
  avatar_color smallint not null default 0,
  visibility text not null default 'private',
  share_ratings boolean not null default false,
  created_at timestamptz not null default now(),
  -- Apple's refresh token, from the sign-in authorization code. Held so
  -- DELETE /v1/me can revoke the Sign in with Apple grant (rule 4.8).
  apple_refresh_token text,
  constraint profiles_handle_key unique (handle),
  constraint profiles_handle_format check (handle ~ '^[a-z0-9_]{3,20}$'),
  constraint profiles_display_name_len check (char_length(display_name) between 1 and 30),
  constraint profiles_avatar_range check (avatar_color between 0 and 10),
  constraint profiles_visibility_values check (visibility in ('private', 'friends'))
);

-- One viewing of a film. The router fills the derived columns from `data`:
--   film_id    = data.film (wire film id: Q<digits> or my:<device>.<n>)
--   rating     = data.rating (0.1 to 5.0) or null
--   private    = data.priv is true
--   watched_on = data.date when data.prec is 'day'
-- `watched_on` only orders results and decides feed freshness. No response
-- carries it. `feed_seq` is set by the upsert SQL when the stub is public and
-- fresh (day precision, watched_on within 14 days of now, not private, not
-- deleted). An edit keeps an existing value. A tombstone has deleted_at set,
-- film_id null, and data '{}'.
create table stubs (
  user_id uuid not null references profiles (id) on delete cascade,
  id text not null,
  film_id text,
  rating double precision,
  private boolean not null default false,
  watched_on date,
  film jsonb,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  seq bigint not null,
  feed_seq bigint,
  primary key (user_id, id),
  constraint stubs_id_len check (char_length(id) between 1 and 64),
  constraint stubs_film_id_format check (film_id ~ '^(Q[0-9]{1,12}|my:[A-Za-z0-9_.-]{1,40})$'),
  constraint stubs_rating_range check (rating between 0.1 and 5.0),
  constraint stubs_live_has_film check (deleted_at is not null or film_id is not null),
  constraint stubs_film_size check (octet_length(film::text) <= 5120),
  constraint stubs_data_size check (octet_length(data::text) <= 20480)
);
create index stubs_user_seq on stubs (user_id, seq);
create index stubs_feed_seq on stubs (feed_seq desc) where feed_seq is not null;
create index stubs_film on stubs (film_id) where deleted_at is null and not private;

-- Watchlist entry. film_id is the wire film id.
create table wishes (
  user_id uuid not null references profiles (id) on delete cascade,
  film_id text not null,
  film jsonb,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  seq bigint not null,
  primary key (user_id, film_id),
  constraint wishes_film_id_format check (film_id ~ '^(Q[0-9]{1,12}|my:[A-Za-z0-9_.-]{1,40})$'),
  constraint wishes_film_size check (octet_length(film::text) <= 5120),
  constraint wishes_data_size check (octet_length(data::text) <= 4096)
);
create index wishes_user_seq on wishes (user_id, seq);

-- One document per kind: `meta` (tags, venues, hidden) and `taste`.
create table user_docs (
  user_id uuid not null references profiles (id) on delete cascade,
  kind text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  seq bigint not null,
  primary key (user_id, kind),
  constraint user_docs_kind_values check (kind in ('meta', 'taste')),
  constraint user_docs_data_size check (
    octet_length(data::text) <= case kind when 'taste' then 30720 else 81920 end
  )
);
create index user_docs_user_seq on user_docs (user_id, seq);

create function set_sync_seq() returns trigger
language plpgsql
as $$
begin
  new.seq := nextval('public.sync_seq');
  return new;
end
$$;

create trigger stubs_set_seq before insert or update on stubs
  for each row execute function set_sync_seq();
create trigger wishes_set_seq before insert or update on wishes
  for each row execute function set_sync_seq();
create trigger user_docs_set_seq before insert or update on user_docs
  for each row execute function set_sync_seq();

-- Account deletion. Everything cascades from profiles (phase 3 adds a trigger
-- that hands owned groups to another member first). The backend commits this,
-- then deletes the Supabase Auth user.
create function delete_account(p_user uuid) returns void
language plpgsql
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user::text, 0));
  delete from profiles where id = p_user;
end
$$;

-- Footer: RLS on with no policy, and no access for the public API roles.
alter table profiles enable row level security;
alter table stubs enable row level security;
alter table wishes enable row level security;
alter table user_docs enable row level security;

revoke all on table profiles, stubs, wishes, user_docs from anon, authenticated;
revoke all on sequence sync_seq, feed_seq from anon, authenticated;
revoke all on function set_sync_seq(), delete_account(uuid) from public, anon, authenticated;
