-- A repayment day per ledger (موعد السداد). The owner sets or clears it and
-- both sides see it; it is information only and never moves a balance.
-- The ledgers_update policy already limits updates to the owner, so the
-- other party's update finds no row. Nullable: most ledgers have none.
alter table public.ledgers add column due_on date;

grant update (due_on) on public.ledgers to authenticated;
