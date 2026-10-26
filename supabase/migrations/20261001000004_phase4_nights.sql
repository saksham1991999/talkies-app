-- Phase 4: movie nights, options, votes, RSVPs.

-- Header: new objects get no grant for the public API roles.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges revoke execute on functions from public;

-- host_id is the host's user id (profile id). It becomes null when the host
-- deletes the account, so the night stays for the others.
-- Status: poll (voting), set (event fixed), done (wrap-up ran).
-- tz_offset_min is the group's clock offset from UTC at creation, in minutes.
create table nights (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups (id) on delete cascade,
  host_id uuid references profiles (id) on delete set null,
  status text not null default 'poll',
  tz_offset_min integer not null,
  place text,
  created_at timestamptz not null default now(),
  constraint nights_status_values check (status in ('poll', 'set', 'done')),
  constraint nights_tz_range check (tz_offset_min between -840 and 840),
  constraint nights_place_len check (char_length(place) <= 80)
);
create index nights_group on nights (group_id, created_at desc);

-- A film option (kind film) or a time slot (kind slot). `position` is the
-- order inside its kind and breaks vote ties. `chosen` marks the winners of a
-- night that is set: at most one film and one slot.
create table night_options (
  id uuid primary key default gen_random_uuid(),
  night_id uuid not null references nights (id) on delete cascade,
  kind text not null,
  position smallint not null,
  film_id text,
  film jsonb,
  starts_at timestamptz,
  chosen boolean not null default false,
  constraint night_options_position_key unique (night_id, kind, position),
  constraint night_options_kind_values check (kind in ('film', 'slot')),
  constraint night_options_position_range check (position between 0 and 2),
  constraint night_options_shape check (
    (kind = 'film' and film_id is not null and film is not null and starts_at is null)
    or (kind = 'slot' and starts_at is not null and film_id is null and film is null)
  ),
  constraint night_options_film_id check (film_id ~ '^Q[0-9]{1,12}$'),
  constraint night_options_film_size check (octet_length(film::text) <= 5120)
);
create unique index night_options_chosen on night_options (night_id, kind) where chosen;

-- Approval voting: a row means the member approves the option.
create table night_votes (
  option_id uuid not null references night_options (id) on delete cascade,
  member_id uuid not null references group_members (id) on delete cascade,
  primary key (option_id, member_id)
);
create index night_votes_member on night_votes (member_id);

create table night_rsvps (
  night_id uuid not null references nights (id) on delete cascade,
  member_id uuid not null references group_members (id) on delete cascade,
  response text not null,
  primary key (night_id, member_id),
  constraint night_rsvps_response_values check (response in ('yes', 'no', 'maybe'))
);
create index night_rsvps_member on night_rsvps (member_id);

-- Footer: RLS on with no policy, and no access for the public API roles.
alter table nights enable row level security;
alter table night_options enable row level security;
alter table night_votes enable row level security;
alter table night_rsvps enable row level security;

revoke all on table nights, night_options, night_votes, night_rsvps from anon, authenticated;
