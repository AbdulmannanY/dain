-- Dain (دائن) -- core ledger schema
-- A ledger (دفتر) is between its owner (person, optionally acting as a business)
-- and one counterparty identified by phone. Entries are recorded by either side
-- and confirmed or disputed by the OTHER side.
--
-- Sign convention (always relative to the ledger OWNER):
--   direction 'out' = owner gave to counterparty   -> counterparty owes more
--   direction 'in'  = counterparty gave to owner    -> counterparty owes less
--   balance > 0     = counterparty owes owner; balance < 0 = owner owes counterparty
-- Amounts are integers in minor units (halalas): 500.00 SAR = 50000.

create extension if not exists pgcrypto with schema extensions;

create type public.entry_direction as enum ('out', 'in');
create type public.entry_status as enum ('pending', 'confirmed', 'disputed', 'voided');

-- ---------------------------------------------------------------- tables

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null check (char_length(full_name) between 1 and 80),
  created_at  timestamptz not null default now()
);

create table public.businesses (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 80),
  created_at  timestamptz not null default now(),
  unique (id, owner_id)
);

create table public.ledgers (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  business_id         uuid,
  counterparty_name   text not null check (char_length(counterparty_name) between 1 and 80),
  -- E.164 digits without '+', e.g. 966501234567
  counterparty_phone  text not null check (counterparty_phone ~ '^[1-9][0-9]{7,14}$'),
  -- set only by link_my_ledgers() after the counterparty verifies that phone
  counterparty_id     uuid references public.profiles (id) on delete set null,
  currency            char(3) not null default 'SAR' check (currency ~ '^[A-Z]{3}$'),
  remind_every_days   smallint check (remind_every_days between 1 and 90),
  last_reminded_at    timestamptz,
  created_at          timestamptz not null default now(),
  -- a business ledger must belong to a business owned by the same owner
  foreign key (business_id, owner_id) references public.businesses (id, owner_id),
  check (counterparty_id is null or counterparty_id <> owner_id),
  unique nulls not distinct (owner_id, business_id, counterparty_phone)
);

create index ledgers_owner_idx        on public.ledgers (owner_id);
create index ledgers_counterparty_idx on public.ledgers (counterparty_id);
create index ledgers_phone_idx        on public.ledgers (counterparty_phone) where counterparty_id is null;

create table public.entries (
  id             uuid primary key default gen_random_uuid(),
  ledger_id      uuid not null references public.ledgers (id) on delete cascade,
  direction      public.entry_direction not null,
  amount_minor   bigint not null check (amount_minor > 0 and amount_minor <= 100000000000),
  note           text check (char_length(note) <= 200),
  occurred_on    date not null default current_date,
  status         public.entry_status not null default 'pending',
  response_note  text check (char_length(response_note) <= 200),
  responded_at   timestamptz,
  responded_via  text check (responded_via in ('app', 'link')),
  created_by     uuid not null default auth.uid() references public.profiles (id),
  created_at     timestamptz not null default now()
);

create index entries_ledger_idx on public.entries (ledger_id, created_at desc);

-- one active share link per ledger; only the SHA-256 of the token is stored
create table public.share_links (
  ledger_id   uuid primary key references public.ledgers (id) on delete cascade,
  token_hash  bytea not null unique,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------- balances

create view public.ledger_balances with (security_invoker = true) as
select
  l.id as ledger_id,
  coalesce(sum(case when e.direction = 'out' then e.amount_minor else -e.amount_minor end)
           filter (where e.status = 'confirmed'), 0)              as confirmed_balance_minor,
  coalesce(sum(case when e.direction = 'out' then e.amount_minor else -e.amount_minor end)
           filter (where e.status in ('pending', 'confirmed')), 0) as open_balance_minor,
  count(e.id) filter (where e.status = 'pending')                   as pending_count,
  count(e.id) filter (where e.status = 'disputed')                  as disputed_count
from public.ledgers l
left join public.entries e on e.ledger_id = l.id
group by l.id;

-- ---------------------------------------------------------------- RLS

alter table public.profiles    enable row level security;
alter table public.businesses  enable row level security;
alter table public.ledgers     enable row level security;
alter table public.entries     enable row level security;
alter table public.share_links enable row level security;  -- no policies: functions only

create policy profiles_select on public.profiles for select to authenticated using (
  id = auth.uid()
  or exists (
    select 1 from public.ledgers l
    where (l.owner_id = profiles.id and l.counterparty_id = auth.uid())
       or (l.counterparty_id = profiles.id and l.owner_id = auth.uid())
  )
);
create policy profiles_insert on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy businesses_select on public.businesses for select to authenticated using (
  owner_id = auth.uid()
  or exists (select 1 from public.ledgers l
             where l.business_id = businesses.id and l.counterparty_id = auth.uid())
);
create policy businesses_insert on public.businesses for insert to authenticated with check (owner_id = auth.uid());
create policy businesses_update on public.businesses for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy businesses_delete on public.businesses for delete to authenticated using (owner_id = auth.uid());

create policy ledgers_select on public.ledgers for select to authenticated
  using (owner_id = auth.uid() or counterparty_id = auth.uid());
create policy ledgers_insert on public.ledgers for insert to authenticated
  with check (owner_id = auth.uid() and counterparty_id is null);
create policy ledgers_update on public.ledgers for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- no delete policy: a ledger is a shared record and cannot be deleted by one side

create policy entries_select on public.entries for select to authenticated using (
  exists (select 1 from public.ledgers l where l.id = entries.ledger_id
          and (l.owner_id = auth.uid() or l.counterparty_id = auth.uid()))
);
create policy entries_insert on public.entries for insert to authenticated with check (
  created_by = auth.uid()
  and status = 'pending'
  and exists (select 1 from public.ledgers l where l.id = entries.ledger_id
              and (l.owner_id = auth.uid() or l.counterparty_id = auth.uid()))
);
-- no update/delete policies: status changes go through the functions below

-- ---------------------------------------------------------------- grants
-- Supabase grants ALL to anon/authenticated by default; narrow it explicitly.

revoke all on public.profiles, public.businesses, public.ledgers, public.entries,
              public.share_links, public.ledger_balances
  from anon, authenticated;

grant select on public.profiles to authenticated;
grant insert (id, full_name), update (full_name) on public.profiles to authenticated;

grant select, delete on public.businesses to authenticated;
grant insert (owner_id, name), update (name) on public.businesses to authenticated;

grant select on public.ledgers to authenticated;
grant insert (owner_id, business_id, counterparty_name, counterparty_phone, currency, remind_every_days)
  on public.ledgers to authenticated;
grant update (counterparty_name, counterparty_phone, remind_every_days) on public.ledgers to authenticated;

grant select on public.entries to authenticated;
grant insert (ledger_id, direction, amount_minor, note, occurred_on) on public.entries to authenticated;

grant select on public.ledger_balances to authenticated;

-- ---------------------------------------------------------------- triggers

-- the phone can be corrected only before the counterparty has linked;
-- any correction kills the share link that went to the wrong number
create function public._ledgers_guard_phone() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.counterparty_phone is distinct from old.counterparty_phone then
    if old.counterparty_id is not null then
      raise exception 'counterparty already linked; phone cannot change' using errcode = '55000';
    end if;
    delete from public.share_links where ledger_id = old.id;
  end if;
  return new;
end $$;

create trigger ledgers_guard_phone before update on public.ledgers
  for each row execute function public._ledgers_guard_phone();

-- ---------------------------------------------------------------- functions

create function public._apply_response(
  p_entry public.entries, p_decision public.entry_status, p_note text, p_via text
) returns public.entry_status
language plpgsql security definer set search_path = '' as $$
begin
  if p_decision is null or p_decision not in ('confirmed', 'disputed') then
    raise exception 'decision must be confirmed or disputed' using errcode = '22023';
  end if;
  -- pending -> confirmed|disputed ; disputed -> confirmed (after the two sides settle it)
  if not (p_entry.status = 'pending' or (p_entry.status = 'disputed' and p_decision = 'confirmed')) then
    raise exception 'entry is %, cannot become %', p_entry.status, p_decision using errcode = '55000';
  end if;
  update public.entries
     set status = p_decision, response_note = p_note, responded_at = now(), responded_via = p_via
   where id = p_entry.id;
  return p_decision;
end $$;

-- the other party of the ledger confirms or disputes an entry
create function public.respond_entry(
  p_entry_id uuid, p_decision public.entry_status, p_note text default null
) returns public.entry_status
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  e  public.entries;
  l  public.ledgers;
begin
  select * into e from public.entries where id = p_entry_id for update;
  if found then
    select * into l from public.ledgers where id = e.ledger_id;
  end if;
  if not found or me is null
     or (me is distinct from l.owner_id and me is distinct from l.counterparty_id) then
    raise exception 'entry not found' using errcode = 'P0002';
  end if;
  if me = e.created_by then
    raise exception 'cannot respond to your own entry' using errcode = '42501';
  end if;
  return public._apply_response(e, p_decision, p_note, 'app');
end $$;

-- the creator withdraws an entry that is still pending or was disputed;
-- confirmed entries are corrected with a new opposite entry, never edited
create function public.void_entry(p_entry_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.entries;
begin
  select * into e from public.entries where id = p_entry_id for update;
  if not found or e.created_by is distinct from auth.uid() then
    raise exception 'entry not found' using errcode = 'P0002';
  end if;
  if e.status not in ('pending', 'disputed') then
    raise exception 'entry is %, cannot be voided', e.status using errcode = '55000';
  end if;
  update public.entries set status = 'voided' where id = e.id;
end $$;

-- after phone OTP sign-in: attach every ledger recorded against my VERIFIED phone
create function public.link_my_ledgers() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  me      uuid := auth.uid();
  v_phone text;
  n       integer;
begin
  if me is null or not exists (select 1 from public.profiles where id = me) then
    raise exception 'profile required' using errcode = '42501';
  end if;
  select ltrim(u.phone, '+') into v_phone
    from auth.users u
   where u.id = me and u.phone_confirmed_at is not null and coalesce(u.phone, '') <> '';
  if v_phone is null then
    return 0;
  end if;
  update public.ledgers
     set counterparty_id = me
   where counterparty_phone = v_phone and counterparty_id is null and owner_id <> me;
  get diagnostics n = row_count;
  return n;
end $$;

-- owner creates (or rotates) the link sent to the counterparty over WhatsApp/SMS.
-- The plain token is returned once and never stored.
create function public.create_share_link(p_ledger_id uuid, p_days integer default 30) returns text
language plpgsql security definer set search_path = '' as $$
declare v_token text;
begin
  if p_days is null or p_days not between 1 and 90 then
    raise exception 'days must be 1..90' using errcode = '22023';
  end if;
  if not exists (select 1 from public.ledgers where id = p_ledger_id and owner_id = auth.uid()) then
    raise exception 'ledger not found' using errcode = 'P0002';
  end if;
  v_token := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_');
  insert into public.share_links (ledger_id, token_hash, expires_at)
  values (p_ledger_id, extensions.digest(v_token, 'sha256'), now() + make_interval(days => p_days))
  on conflict (ledger_id) do update
    set token_hash = excluded.token_hash, expires_at = excluded.expires_at, created_at = now();
  return v_token;
end $$;

create function public.revoke_share_link(p_ledger_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.share_links s
   using public.ledgers l
   where s.ledger_id = l.id and l.id = p_ledger_id and l.owner_id = auth.uid();
end $$;

create function public._ledger_from_token(p_token text) returns public.ledgers
language plpgsql security definer set search_path = '' as $$
declare l public.ledgers;
begin
  if p_token is null or length(p_token) <> 32 then
    raise exception 'invalid or expired link' using errcode = 'P0002';
  end if;
  select l2.* into l
    from public.share_links s
    join public.ledgers l2 on l2.id = s.ledger_id
   where s.token_hash = extensions.digest(p_token, 'sha256') and s.expires_at > now();
  if not found then
    raise exception 'invalid or expired link' using errcode = 'P0002';
  end if;
  return l;
end $$;

-- web confirmation page (no app install): read the ledger behind a link
create function public.get_shared_ledger(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare l public.ledgers;
begin
  l := public._ledger_from_token(p_token);
  return (
    select jsonb_build_object(
      'owner_name',        coalesce(b.name, p.full_name),
      'counterparty_name', l.counterparty_name,
      'currency',          l.currency,
      'confirmed_balance_minor', coalesce((
          select sum(case when e.direction = 'out' then e.amount_minor else -e.amount_minor end)
            from public.entries e where e.ledger_id = l.id and e.status = 'confirmed'), 0),
      'entries', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'id', x.id, 'direction', x.direction, 'amount_minor', x.amount_minor,
                   'note', x.note, 'occurred_on', x.occurred_on, 'status', x.status,
                   'can_respond', x.created_by = l.owner_id and x.status in ('pending', 'disputed'))
                 order by x.created_at desc)
            from (select * from public.entries e
                   where e.ledger_id = l.id and e.status <> 'voided'
                   order by e.created_at desc limit 100) x), '[]'::jsonb)
    )
    from public.profiles p
    left join public.businesses b on b.id = l.business_id
    where p.id = l.owner_id
  );
end $$;

-- web confirmation page: counterparty confirms/disputes an entry the OWNER recorded
create function public.respond_by_token(
  p_token text, p_entry_id uuid, p_decision public.entry_status, p_note text default null
) returns public.entry_status
language plpgsql security definer set search_path = '' as $$
declare
  l public.ledgers;
  e public.entries;
begin
  l := public._ledger_from_token(p_token);
  select * into e from public.entries where id = p_entry_id and ledger_id = l.id for update;
  if not found or e.created_by <> l.owner_id then
    raise exception 'entry not found' using errcode = 'P0002';
  end if;
  return public._apply_response(e, p_decision, p_note, 'link');
end $$;

-- ---------------------------------------------------------------- function grants

revoke execute on function
  public._ledgers_guard_phone(),
  public._apply_response(public.entries, public.entry_status, text, text),
  public._ledger_from_token(text),
  public.respond_entry(uuid, public.entry_status, text),
  public.void_entry(uuid),
  public.link_my_ledgers(),
  public.create_share_link(uuid, integer),
  public.revoke_share_link(uuid),
  public.get_shared_ledger(text),
  public.respond_by_token(text, uuid, public.entry_status, text)
from public, anon, authenticated;

grant execute on function
  public.respond_entry(uuid, public.entry_status, text),
  public.void_entry(uuid),
  public.link_my_ledgers(),
  public.create_share_link(uuid, integer),
  public.revoke_share_link(uuid)
to authenticated;

grant execute on function
  public.get_shared_ledger(text),
  public.respond_by_token(text, uuid, public.entry_status, text)
to anon, authenticated;
