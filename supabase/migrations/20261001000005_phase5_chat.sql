-- Phase 5: chat and sent films.

-- Header: new objects get no grant for the public API roles.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges revoke execute on functions from public;

-- A text message has a sender and a body. A system message has a code and
-- args (the phone writes the text in its own language) and no sender.
-- Deleting the sender's account deletes their messages.
-- `subject_id` is the user a system message is about (joined, left). It
-- cascades too, so a name in a notice does not outlive the account.
create table messages (
  id bigint generated always as identity primary key,
  group_id uuid not null references groups (id) on delete cascade,
  sender_id uuid references profiles (id) on delete cascade,
  subject_id uuid references profiles (id) on delete cascade,
  kind text not null,
  body text,
  code text,
  args jsonb,
  film_id text,
  film jsonb,
  night_id uuid references nights (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint messages_kind_values check (kind in ('text', 'system')),
  constraint messages_shape check (
    (kind = 'text' and sender_id is not null and subject_id is null and body is not null and code is null)
    or (kind = 'system' and sender_id is null and body is null and code is not null)
  ),
  constraint messages_body_len check (char_length(body) between 1 and 1000),
  constraint messages_code_len check (char_length(code) between 1 and 32),
  constraint messages_args_size check (octet_length(args::text) <= 1024),
  constraint messages_film_id check (film_id ~ '^Q[0-9]{1,12}$'),
  constraint messages_film_size check (octet_length(film::text) <= 5120)
);
create index messages_group on messages (group_id, id desc);
create index messages_sender on messages (sender_id);
create index messages_subject on messages (subject_id);

-- A film sent to a friend. It shows in the receiver's feed as `sent`.
create table sent_films (
  feed_seq bigint primary key default nextval('public.feed_seq'),
  sender_id uuid not null references profiles (id) on delete cascade,
  receiver_id uuid not null references profiles (id) on delete cascade,
  film_id text not null,
  film jsonb not null,
  note text,
  created_at timestamptz not null default now(),
  constraint sent_films_film_id check (film_id ~ '^Q[0-9]{1,12}$'),
  constraint sent_films_not_self check (sender_id <> receiver_id),
  constraint sent_films_note_len check (char_length(note) <= 140),
  constraint sent_films_film_size check (octet_length(film::text) <= 5120)
);
create index sent_films_receiver on sent_films (receiver_id, feed_seq desc);
create index sent_films_sender on sent_films (sender_id);

-- Footer: RLS on with no policy, and no access for the public API roles.
alter table messages enable row level security;
alter table sent_films enable row level security;

revoke all on table messages, sent_films from anon, authenticated;
