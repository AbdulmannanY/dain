-- Deleting my account from the app (Google Play requires it for any app
-- with accounts). Removing the auth user cascades to my profile, my shops,
-- the ledgers I own and their entries and links. A ledger someone else owns
-- is a shared record and stays with its owner: it is unlinked from me
-- (counterparty_id is already "on delete set null"), and the entries I
-- recorded in it stay too, with created_by set to null.
alter table public.entries alter column created_by drop not null;
alter table public.entries drop constraint entries_created_by_fkey;
alter table public.entries add constraint entries_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete set null;

-- With created_by possibly null, a link must still answer only the owner's
-- entries ("<>" let a null through). Same signature: grants stay.
create or replace function public.respond_by_token(
  p_token text, p_entry_id uuid, p_decision public.entry_status, p_note text default null
) returns public.entry_status
language plpgsql security definer set search_path = '' as $$
declare
  l public.ledgers;
  e public.entries;
begin
  l := public._ledger_from_token(p_token);
  select * into e from public.entries where id = p_entry_id and ledger_id = l.id for update;
  if not found or e.created_by is distinct from l.owner_id then
    raise exception 'entry not found' using errcode = 'P0002';
  end if;
  return public._apply_response(e, p_decision, p_note, 'link');
end $$;

create function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke execute on function public.delete_my_account() from public, anon, service_role;
grant execute on function public.delete_my_account() to authenticated;
