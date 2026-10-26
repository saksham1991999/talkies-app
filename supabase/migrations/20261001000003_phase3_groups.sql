-- Phase 3: groups, shared list, deck, swipes.

-- Header: new objects get no grant for the public API roles.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges revoke execute on functions from public;

-- owner_id is ON DELETE RESTRICT on purpose. The BEFORE DELETE trigger on
-- profiles (below) hands the group over or deletes it first. If that ever
-- fails, deleting the profile fails loudly instead of orphaning a group.
create table groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references profiles (id) on delete restrict,
  invite_code text not null,
  created_at timestamptz not null default now(),
  constraint groups_invite_code_key unique (invite_code),
  constraint groups_name_len check (char_length(name) between 1 and 40),
  constraint groups_invite_code_format check (invite_code ~ '^[A-HJ-KM-NP-Z2-9]{8}$')
);
create index groups_owner on groups (owner_id);

-- A member is an account (user_id) or a guest (user_id null, guest_name set).
create table group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups (id) on delete cascade,
  user_id uuid references profiles (id) on delete cascade,
  guest_name text,
  joined_at timestamptz not null default now(),
  constraint group_members_user_key unique (group_id, user_id),
  constraint group_members_kind check ((user_id is null) <> (guest_name is null)),
  constraint group_members_guest_len check (char_length(guest_name) between 1 and 40)
);
create unique index group_members_guest_name
  on group_members (group_id, lower(guest_name))
  where guest_name is not null;
create index group_members_user on group_members (user_id);

-- The shared watchlist. QID films only. The snapshot is the app's film JSON.
create table group_films (
  group_id uuid not null references groups (id) on delete cascade,
  film_id text not null,
  film jsonb not null,
  added_at timestamptz not null default now(),
  primary key (group_id, film_id),
  constraint group_films_film_id check (film_id ~ '^Q[0-9]{1,12}$'),
  constraint group_films_film_size check (octet_length(film::text) <= 5120)
);

-- One deck per group. `version` counts uploads. `items` is an array of
-- {film_id, film}. The backend creates the row (version 0) with the group.
create table group_decks (
  group_id uuid primary key references groups (id) on delete cascade,
  version integer not null default 0,
  items jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  constraint group_decks_items_array check (jsonb_typeof(items) = 'array'),
  constraint group_decks_items_size check (octet_length(items::text) <= 700000)
);

-- One vote per member and film. Deleting a member deletes their swipes.
create table swipes (
  group_id uuid not null references groups (id) on delete cascade,
  member_id uuid not null references group_members (id) on delete cascade,
  film_id text not null,
  vote text not null,
  primary key (member_id, film_id),
  constraint swipes_vote_values check (vote in ('want', 'skip', 'seen')),
  constraint swipes_film_id check (film_id ~ '^Q[0-9]{1,12}$')
);
create index swipes_group_film on swipes (group_id, film_id);

-- Every member's watchlist, by group. No user id: a deck input never names a member.
create view v_group_wishes with (security_invoker = true) as
  select m.group_id, w.film_id, w.film
  from group_members m
  join wishes w on w.user_id = m.user_id
  where w.deleted_at is null
    and w.film_id ~ '^Q[0-9]{1,12}$';

-- Every member's taste document, by group. No user id.
create view v_group_tastes with (security_invoker = true) as
  select m.group_id, d.data as taste
  from group_members m
  join user_docs d on d.user_id = m.user_id
  where d.kind = 'taste'
    and d.deleted_at is null;

-- Deleting a profile: hand each owned group to the earliest-joined linked
-- member, or delete the group when nobody else is left. The loop locks the
-- groups, so a member who leaves at the same moment waits for this commit.
create function hand_over_groups() returns trigger
language plpgsql
as $$
declare
  g record;
  heir uuid;
begin
  for g in select id from groups where owner_id = old.id for update loop
    select user_id into heir
    from group_members
    where group_id = g.id and user_id is not null and user_id <> old.id
    order by joined_at, id
    limit 1;
    if heir is null then
      delete from groups where id = g.id;
    else
      update groups set owner_id = heir where id = g.id;
    end if;
  end loop;
  return old;
end
$$;

create trigger profiles_hand_over_groups before delete on profiles
  for each row execute function hand_over_groups();

-- Footer: RLS on with no policy, and no access for the public API roles.
alter table groups enable row level security;
alter table group_members enable row level security;
alter table group_films enable row level security;
alter table group_decks enable row level security;
alter table swipes enable row level security;

revoke all on table groups, group_members, group_films, group_decks, swipes from anon, authenticated;
revoke all on table v_group_wishes, v_group_tastes from anon, authenticated;
revoke all on function hand_over_groups() from public, anon, authenticated;
