-- The few parts of Supabase that the migrations touch, for a plain Postgres test database.
-- Hosted Supabase and `supabase start` already have all of this.

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  email text
);

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin;
  end if;
end
$$;

-- The tests use SET ROLE to prove that the public API roles are locked out.
grant anon, authenticated, service_role to current_user;
