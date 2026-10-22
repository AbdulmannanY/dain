#!/usr/bin/env bash
# Sends at the same moment what a slow network or two phones would:
#  1. five payments of 30.00 against 100.00 owed: the payment guard locks
#     the ledger row, so they are checked one after the other; exactly
#     three go through (90.00) and two are refused with 23514.
#  2. the same entry id twice: exactly one is saved, the other is 23505.
# Each session holds its transaction open for a moment, so without the
# lock every payment would see none of the others and all five would pass.
# Run by run_tests.sh, with the same PG* variables, on its own database.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=dain_concurrency
A=aaaaaaaa-0000-0000-0000-000000000001
B=bbbbbbbb-0000-0000-0000-000000000002
L=cccccccc-0000-4000-8000-000000000003
ID=dddddddd-0000-4000-8000-000000000004
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; psql -qc "drop database if exists $DB" >/dev/null' EXIT

psql -qc "drop database if exists $DB" -c "create database $DB" >/dev/null
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f tests/supabase_stub.sql
for f in migrations/*.sql; do psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"; done
# B owes A 100.00 on an agreed entry (written as the superuser).
psql -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL
insert into auth.users values ('$A', '966500000001', now()), ('$B', '966500000002', now());
insert into public.profiles (id, full_name) values ('$A', 'A'), ('$B', 'B');
insert into public.ledgers (id, owner_id, counterparty_name, counterparty_phone, counterparty_id)
values ('$L', '$A', 'B', '966500000002', '$B');
insert into public.entries (ledger_id, direction, amount_minor, status, created_by)
values ('$L', 'out', 10000, 'confirmed', '$A');
SQL

# As B, in one transaction held open for a second: $1 names the run, $2
# adds columns to the insert and $3 the matching values.
send() {
  if psql -X -q -v ON_ERROR_STOP=1 -d "$DB" >/dev/null 2>"$tmp/$1.err" <<SQL
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"$B"}';
insert into public.entries (ledger_id, direction, amount_minor$2) values ('$L', 'in'$3);
select pg_sleep(1);
commit;
SQL
  then echo ok > "$tmp/$1.out"; else echo refused > "$tmp/$1.out"; fi
}

for i in 1 2 3 4 5; do send "pay$i" ", kind" ", 3000, 'payment'" & done
wait
ok=$(cat "$tmp"/pay*.out | grep -c '^ok$' || true)
over=$(cat "$tmp"/pay*.err | grep -c 'payment exceeds what is owed' || true)
held=$(psql -tAq -d "$DB" -c "select sum(amount_minor) from public.entries where kind = 'payment'")
echo "payments at once: $ok saved, $over refused, $held held"
[ "$ok" = 3 ] && [ "$over" = 2 ] && [ "$held" = 9000 ] || {
  echo "FAIL: five payments of 30 against 100 owed"; cat "$tmp"/pay*.err; exit 1; }

for i in 1 2; do send "dup$i" ", id" ", 100, '$ID'" & done
wait
saved=$(psql -tAq -d "$DB" -c "select count(*) from public.entries where id = '$ID'")
dup=$(cat "$tmp"/dup*.err | grep -c 'duplicate key' || true)
echo "the same id twice at once: $saved saved, $dup refused"
[ "$saved" = 1 ] && [ "$dup" = 1 ] || {
  echo "FAIL: the same id sent twice"; cat "$tmp"/dup*.err; exit 1; }

echo "CONCURRENCY TESTS PASSED"
