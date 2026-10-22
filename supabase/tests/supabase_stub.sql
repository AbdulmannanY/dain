-- Minimal stand-in for the parts of Supabase the migration relies on.
-- Used only to run the tests on a plain PostgreSQL 15+.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then create role supabase_auth_admin nologin; end if;
end $$;

create schema auth;
create schema extensions;

create table auth.users (
  id                 uuid primary key,
  phone              text unique,
  phone_confirmed_at timestamptz
);

create function auth.uid() returns uuid language sql stable as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;

grant usage on schema public, auth, extensions to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Supabase's default: everything new in public is granted to these roles
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;

-- pg_net and Vault, as far as the Send SMS hook uses them: http_post records
-- the request instead of sending it, and secrets are plain text.
create schema net;
create table net.sent (
  url text, body jsonb, headers jsonb, timeout_milliseconds int
);
create function net.http_post(
  url text, body jsonb default '{}', params jsonb default '{}',
  headers jsonb default '{}', timeout_milliseconds int default 5000
) returns bigint language sql as $$
  insert into net.sent values (url, body, headers, timeout_milliseconds);
  select 1::bigint;
$$;

create schema vault;
create table vault.decrypted_secrets (name text primary key, decrypted_secret text);
