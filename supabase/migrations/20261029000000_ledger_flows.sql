-- What the financial dashboard needs beyond ledger_balances: the confirmed
-- payments of each day (collected and paid in a period), and the amounts
-- still pending or disputed, kept apart from the agreed balance.
--
-- One row per ledger, status, direction and, for a confirmed payment, its
-- day: occurred_on, the day the money changed hands as recorded (null for
-- the pending and disputed rows). Confirmed debts are not here: the agreed
-- balance already holds them. Directions stay relative to the ledger owner,
-- as everywhere; the app turns them to the viewer's side.
--
-- Security invoker: the same RLS as entries, so each side sees only the
-- ledgers it owns or is linked to. Reading only; a view is never written.
create view public.ledger_flows with (security_invoker = true) as
select e.ledger_id,
       e.status,
       e.direction,
       case when e.status = 'confirmed' then e.occurred_on end as paid_on,
       sum(e.amount_minor)::bigint as amount_minor,
       count(*)::integer as entry_count
  from public.entries e
 where e.status in ('pending', 'disputed')
    or (e.status = 'confirmed' and e.kind = 'payment')
 group by e.ledger_id, e.status, e.direction, 4;

revoke all on public.ledger_flows from anon, authenticated;
grant select on public.ledger_flows to authenticated;
