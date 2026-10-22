-- An audit trail of every entry: created, confirmed, disputed, withdrawn,
-- with who did it, how (the app or the share link) and when. Only triggers
-- write it (no user may insert, change or delete a row), and both sides of
-- the ledger read it. It answers "who confirmed this, and when?" after the
-- fact, which entries.responded_at alone cannot once a dispute is settled.
create table public.entry_events (
  id         bigint generated always as identity primary key,
  entry_id   uuid not null references public.entries (id) on delete cascade,
  ledger_id  uuid not null references public.ledgers (id) on delete cascade,
  event      text not null check (event in ('created', 'confirmed', 'disputed', 'voided')),
  -- null after that person deleted the account, or for a link (no account)
  actor      uuid references public.profiles (id) on delete set null,
  via        text check (via in ('app', 'link')),
  note       text,
  at         timestamptz not null default now()
);

create index entry_events_entry_idx on public.entry_events (entry_id, id);

alter table public.entry_events enable row level security;

create policy entry_events_select on public.entry_events for select to authenticated using (
  exists (select 1 from public.ledgers l where l.id = entry_events.ledger_id
          and (l.owner_id = auth.uid() or l.counterparty_id = auth.uid()))
);

revoke all on public.entry_events from anon, authenticated;
grant select on public.entry_events to authenticated;

-- Writes the event for an insert, or for a change of status. The response
-- functions set responded_via ('app' or 'link'); a withdrawal is always
-- from the app. A link has no account: its actor is null.
create function public._entries_log() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.entry_events (entry_id, ledger_id, event, actor, via, at)
    values (new.id, new.ledger_id, 'created', new.created_by, 'app', new.created_at);
  elsif new.status is distinct from old.status then
    insert into public.entry_events (entry_id, ledger_id, event, actor, via, note)
    values (new.id, new.ledger_id, new.status::text, auth.uid(),
            case when new.status = 'voided' then 'app' else new.responded_via end,
            case when new.status = 'disputed' then new.response_note end);
  end if;
  return null;
end $$;

revoke execute on function public._entries_log() from public, anon, authenticated;

create trigger entries_log after insert or update of status on public.entries
  for each row execute function public._entries_log();

-- Entries recorded before this migration: their creation, and their last
-- answer when it has a time. Who answered was not kept then (null); a
-- withdrawal before now has no time, so it is not in the trail.
insert into public.entry_events (entry_id, ledger_id, event, actor, via, at)
select e.id, e.ledger_id, 'created', e.created_by, 'app', e.created_at
  from public.entries e;
insert into public.entry_events (entry_id, ledger_id, event, actor, via, note, at)
select e.id, e.ledger_id, e.status::text, null, e.responded_via,
       case when e.status = 'disputed' then e.response_note end, e.responded_at
  from public.entries e
 where e.status in ('confirmed', 'disputed') and e.responded_at is not null;
