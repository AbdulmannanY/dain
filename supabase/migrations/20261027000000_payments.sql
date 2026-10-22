-- Settling debts. A payment is an entry of kind 'payment': it goes through
-- the same pending -> confirmed / disputed cycle, the other party confirms
-- it, and the agreed balance (ledger_balances, confirmed entries only)
-- stays the single source of the remaining amount. Its direction is the
-- payer's: 'in' = the counterparty paid the owner, 'out' = the owner paid
-- the counterparty.
--
-- 1. kind: 'debt' (every existing entry) or 'payment'.
alter table public.entries add column kind text not null default 'debt'
  check (kind in ('debt', 'payment'));

-- 2. The app makes the entry's id, so a save sent again after a lost
--    answer hits the primary key (23505) instead of recording it twice.
grant insert (id, kind) on public.entries to authenticated;

-- 3. A payment never exceeds what its payer still owes: the agreed balance
--    on the payer's side, less the payer's payments still pending or
--    disputed (a disputed one can still be confirmed). The ledger row is
--    locked first, so two payments sent at the same moment are checked one
--    after the other. Security definer: the counterparty may not lock the
--    owner's row under RLS, and the sums must see every entry.
create function public._entries_guard_payment() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_owed bigint;
  v_held bigint;
begin
  if new.kind <> 'payment' then
    return new;
  end if;
  perform 1 from public.ledgers where id = new.ledger_id for update;
  select coalesce(sum(case when e.direction = 'out' then e.amount_minor else -e.amount_minor end), 0)
    into v_owed
    from public.entries e
   where e.ledger_id = new.ledger_id and e.status = 'confirmed';
  -- what the payer owes: the counterparty owes a positive balance, the owner a negative one
  if new.direction = 'out' then
    v_owed := -v_owed;
  end if;
  select coalesce(sum(e.amount_minor), 0)
    into v_held
    from public.entries e
   where e.ledger_id = new.ledger_id and e.kind = 'payment'
     and e.direction = new.direction and e.status in ('pending', 'disputed');
  if new.amount_minor > v_owed - v_held then
    raise exception 'payment exceeds what is owed (%)', greatest(v_owed - v_held, 0)
      using errcode = '23514';
  end if;
  return new;
end $$;

revoke execute on function public._entries_guard_payment() from public, anon, authenticated;

create trigger entries_guard_payment before insert on public.entries
  for each row execute function public._entries_guard_payment();

-- 4. The share page shows which entries are payments. Same signature and
--    body as in 20261020000000_dain_core.sql, plus 'kind'.
create or replace function public.get_shared_ledger(p_token text) returns jsonb
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
                   'kind', x.kind,
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
