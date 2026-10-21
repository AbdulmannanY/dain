-- Reminders: the owner sets ledgers.remind_every_days (1..90, already
-- grant-updatable); the app shows a reminder as due when the other party
-- owes the owner and the last one is older than that. The owner sends the
-- reminder message the app copies (with a fresh share link) and the app
-- records it here. last_reminded_at is not grant-updatable, so the time is
-- the server's and only the owner can set it.
create function public.mark_reminded(p_ledger_id uuid) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v_at timestamptz;
begin
  update public.ledgers set last_reminded_at = now()
   where id = p_ledger_id and owner_id = auth.uid()
  returning last_reminded_at into v_at;
  if v_at is null then
    raise exception 'ledger not found' using errcode = 'P0002';
  end if;
  return v_at;
end $$;

revoke execute on function public.mark_reminded(uuid) from public, anon, authenticated;
grant execute on function public.mark_reminded(uuid) to authenticated;
