-- End-to-end checks through the real entry points: RLS, grants and RPCs,
-- executed as the same roles Supabase uses (authenticated / anon).
\set ON_ERROR_STOP 1
\set QUIET 1
\o /dev/null

-- ---- helpers (created as superuser) ----
create schema t;
grant usage on schema t to anon, authenticated;
create table t.ids (k text primary key, v uuid);
create table t.tokens (k text primary key, v text);
grant all on t.ids, t.tokens to anon, authenticated;

create function t.ok(p_cond boolean, p_label text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'FAIL: %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

create function t.err(p_sql text, p_code text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'no error';
exception when others then
  if sqlstate <> p_code then
    raise exception 'FAIL: % (expected %, got %: %)', p_label, p_code, sqlstate, sqlerrm;
  end if;
  raise notice 'ok  %', p_label;
end $$;
grant execute on all functions in schema t to anon, authenticated;

-- A owns a grocery; B and C have verified phones; D's phone is NOT verified
insert into auth.users values
  ('aaaaaaaa-0000-0000-0000-000000000001', '+966500000001', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', '966500000002',  now()),
  ('cccccccc-0000-0000-0000-000000000003', '966500000003',  now()),
  ('dddddddd-0000-0000-0000-000000000004', '966500000004',  null);

\set as_A 'reset role; set request.jwt.claims to ''{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}''; set role authenticated;'
\set as_B 'reset role; set request.jwt.claims to ''{"sub":"bbbbbbbb-0000-0000-0000-000000000002"}''; set role authenticated;'
\set as_C 'reset role; set request.jwt.claims to ''{"sub":"cccccccc-0000-0000-0000-000000000003"}''; set role authenticated;'
\set as_D 'reset role; set request.jwt.claims to ''{"sub":"dddddddd-0000-0000-0000-000000000004"}''; set role authenticated;'
\set as_anon 'reset role; set request.jwt.claims to ''''; set role anon;'

-- ================= 1. profiles =================
:as_A
insert into public.profiles (id, full_name) values (auth.uid(), 'Ahmed');
select t.err($$insert into public.profiles (id, full_name) values ('bbbbbbbb-0000-0000-0000-000000000002', 'fake')$$,
             '42501', 'A cannot create a profile for B');
:as_B
insert into public.profiles (id, full_name) values (auth.uid(), 'Badr');
:as_C
insert into public.profiles (id, full_name) values (auth.uid(), 'Saad');
:as_D
insert into public.profiles (id, full_name) values (auth.uid(), 'Dhafer');

-- ================= 2. ledgers =================
:as_A
insert into public.businesses (name) values ('Al-Noor Grocery');
insert into t.ids select 'shop', id from public.businesses;
-- personal ledger with B, shop ledger with C, personal ledger with D (unverified phone)
insert into public.ledgers (counterparty_name, counterparty_phone) values ('Badr', '966500000002');
insert into public.ledgers (business_id, counterparty_name, counterparty_phone)
  select v, 'Saad', '966500000003' from t.ids where k = 'shop';
insert into public.ledgers (counterparty_name, counterparty_phone) values ('Dhafer', '966500000004');
insert into t.ids select 'L_B', id from public.ledgers where counterparty_phone = '966500000002';
insert into t.ids select 'L_C', id from public.ledgers where counterparty_phone = '966500000003';
insert into t.ids select 'L_D', id from public.ledgers where counterparty_phone = '966500000004';
select t.err($$insert into public.ledgers (counterparty_name, counterparty_phone) values ('x', '+966 50')$$,
             '23514', 'phone must be E.164 digits');
select t.err($$insert into public.ledgers (counterparty_name, counterparty_phone, counterparty_id)
               values ('x', '966511111111', 'bbbbbbbb-0000-0000-0000-000000000002')$$,
             '42501', 'A cannot set counterparty_id directly');

:as_C
select t.err($$insert into public.ledgers (business_id, counterparty_name, counterparty_phone)
               select v, 'x', '966522222222' from t.ids where k = 'shop'$$,
             '23503', 'C cannot open a ledger under A''s business');

-- ================= 3. entries by owner =================
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 50000, 'loan' from t.ids where k = 'L_B';
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 10000, 'second loan' from t.ids where k = 'L_B';
insert into t.ids select 'E1', id from public.entries where note = 'loan';
insert into t.ids select 'E2', id from public.entries where note = 'second loan';
select t.err($$update public.entries set status = 'confirmed'$$, '42501', 'A cannot update status directly');
select t.err($$delete from public.ledgers$$, '42501', 'A cannot delete a ledger');
select t.err($$select public.respond_entry((select v from t.ids where k = 'E1'), 'confirmed')$$,
             '42501', 'A cannot confirm own entry');
select t.err($$insert into public.entries (ledger_id, direction, amount_minor) select v, 'out', 0 from t.ids where k = 'L_B'$$,
             '23514', 'amount must be positive');

-- ================= 4. counterparty links and responds =================
:as_B
select t.ok((select count(*) from public.ledgers) = 0, 'B sees nothing before linking');
select t.ok(public.link_my_ledgers() = 1, 'B links exactly one ledger (by verified phone)');
select t.ok((select count(*) from public.entries) = 2, 'B now sees both entries');
select t.ok((select full_name from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'Ahmed',
            'B can see the owner name');
select t.ok(public.respond_entry((select v from t.ids where k = 'E1'), 'confirmed') = 'confirmed', 'B confirms E1');
select t.ok(public.respond_entry((select v from t.ids where k = 'E2'), 'disputed', 'I never took this') = 'disputed',
            'B disputes E2');
select t.err($$select public.respond_entry((select v from t.ids where k = 'E1'), 'disputed')$$,
             '55000', 'confirmed entry cannot be disputed later');
select t.err($$select public.void_entry((select v from t.ids where k = 'E2'))$$,
             'P0002', 'B cannot void A''s entry');
-- B records a repayment; A must confirm it
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'in', 20000, 'paid back 200' from t.ids where k = 'L_B';
insert into t.ids select 'E3', id from public.entries where note = 'paid back 200';
-- RLS filters A's row out of B's update silently; verified as A below
update public.ledgers set counterparty_name = 'hacked';
:as_A
select t.ok((select counterparty_name from public.ledgers where id = (select v from t.ids where k = 'L_B')) = 'Badr',
            'B update on A''s ledger had no effect');
select t.ok(public.respond_entry((select v from t.ids where k = 'E3'), 'confirmed') = 'confirmed', 'A confirms B''s repayment');
select t.ok((select confirmed_balance_minor from public.ledger_balances where ledger_id = (select v from t.ids where k = 'L_B')) = 30000,
            'balance = 500 - 200 = 300 SAR (disputed excluded)');
select public.void_entry((select v from t.ids where k = 'E2'));
select t.ok((select status from public.entries where id = (select v from t.ids where k = 'E2')) = 'voided', 'A voids disputed E2');
select t.err($$update public.ledgers set counterparty_phone = '966599999999' where id = (select v from t.ids where k = 'L_B')$$,
             '55000', 'phone locked after counterparty linked');

-- ================= 5. outsiders =================
:as_C
select t.ok((select count(*) from public.ledgers) = 0, 'C (not linked yet) sees no ledgers');
select t.ok((select count(*) from public.entries) = 0, 'C sees no entries');
select t.ok((select count(*) from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'C cannot see A''s profile');
select t.err($$select public.respond_entry((select v from t.ids where k = 'E1'), 'disputed')$$,
             'P0002', 'C cannot respond to B''s ledger entries');
select t.err($$insert into public.entries (ledger_id, direction, amount_minor) select v, 'in', 100 from t.ids where k = 'L_B'$$,
             '42501', 'C cannot write into B''s ledger');
:as_D
select t.ok(public.link_my_ledgers() = 0, 'D with unverified phone links nothing');
select t.ok((select count(*) from public.ledgers) = 0, 'D sees nothing');
-- ledger whose counterparty never linked (counterparty_id IS NULL)
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 7000, 'to dhafer' from t.ids where k = 'L_D';
insert into t.ids select 'E5', id from public.entries where note = 'to dhafer';
:as_C
select t.err($$select public.respond_entry((select v from t.ids where k = 'E5'), 'confirmed')$$,
             'P0002', 'outsider cannot respond in an unlinked ledger');

-- ================= 6. share link for a customer without the app =================
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 4550, 'groceries' from t.ids where k = 'L_C';
insert into t.ids select 'E4', id from public.entries where note = 'groceries';
insert into t.tokens select 'C', public.create_share_link((select v from t.ids where k = 'L_C'));
:as_B
select t.err($$select public.create_share_link((select v from t.ids where k = 'L_B'))$$,
             'P0002', 'counterparty cannot mint links for owner''s ledger');
:as_anon
select t.err($$select count(*) from public.ledgers$$, '42501', 'anon cannot read tables');
select t.ok((public.get_shared_ledger((select v from t.tokens where k = 'C')) ->> 'owner_name') = 'Al-Noor Grocery',
            'link shows the shop name');
select t.ok(jsonb_array_length(public.get_shared_ledger((select v from t.tokens where k = 'C')) -> 'entries') = 1,
            'link shows the entry');
select t.ok(public.respond_by_token((select v from t.tokens where k = 'C'), (select v from t.ids where k = 'E4'), 'confirmed') = 'confirmed',
            'customer confirms via link');
select t.err($$select public.respond_by_token((select v from t.tokens where k = 'C'), (select v from t.ids where k = 'E1'), 'disputed')$$,
             'P0002', 'link cannot touch entries of another ledger');
select t.err($$select public.get_shared_ledger('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')$$, 'P0002', 'wrong token rejected');
reset role;
update public.share_links set expires_at = now() - interval '1 second';
:as_anon
select t.err($$select public.get_shared_ledger((select v from t.tokens where k = 'C'))$$, 'P0002', 'expired token rejected');
:as_A
select t.ok((select confirmed_balance_minor from public.ledger_balances where ledger_id = (select v from t.ids where k = 'L_C')) = 4550,
            'shop balance 45.50 SAR');
-- correcting an unlinked phone kills the old link
reset role;
update public.share_links set expires_at = now() + interval '1 day';
:as_A
update public.ledgers set counterparty_phone = '966500000033' where id = (select v from t.ids where k = 'L_C');
reset role;
select t.ok((select count(*) from public.share_links) = 0, 'phone correction deletes the share link');

-- ================= 7. a dispute needs its reason (20261021000000) =================
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 1500, 'reason test' from t.ids where k = 'L_B';
insert into t.ids select 'E6', id from public.entries where note = 'reason test';
:as_B
select t.err($$select public.respond_entry((select v from t.ids where k = 'E6'), 'disputed')$$,
             '22023', 'a dispute without a reason is refused');
select t.err($$select public.respond_entry((select v from t.ids where k = 'E6'), 'disputed', '   ')$$,
             '22023', 'a blank reason is refused');
select t.ok(public.respond_entry((select v from t.ids where k = 'E6'), 'disputed', '  wrong amount ') = 'disputed',
            'a dispute with a reason goes through');
select t.ok((select response_note from public.entries where id = (select v from t.ids where k = 'E6')) = 'wrong amount',
            'the reason is stored trimmed');
select t.ok(public.respond_entry((select v from t.ids where k = 'E6'), 'confirmed') = 'confirmed',
            'a disputed entry is still confirmed without a note');
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 800, 'link reason test' from t.ids where k = 'L_C';
insert into t.ids select 'E7', id from public.entries where note = 'link reason test';
insert into t.tokens select 'C2', public.create_share_link((select v from t.ids where k = 'L_C'));
:as_anon
select t.err($$select public.respond_by_token((select v from t.tokens where k = 'C2'), (select v from t.ids where k = 'E7'), 'disputed')$$,
             '22023', 'a dispute by link without a reason is refused');
select t.ok(public.respond_by_token((select v from t.tokens where k = 'C2'), (select v from t.ids where k = 'E7'), 'disputed', 'not mine') = 'disputed',
            'a dispute by link with a reason goes through');
reset role;

-- ================= 8. reminders (20261022000000) =================
:as_A
update public.ledgers set remind_every_days = 7 where id = (select v from t.ids where k = 'L_B');
select t.ok((select remind_every_days from public.ledgers where id = (select v from t.ids where k = 'L_B')) = 7,
            'the owner sets a reminder every 7 days');
select t.err($$update public.ledgers set remind_every_days = 0 where id = (select v from t.ids where k = 'L_B')$$,
             '23514', 'a reminder period of 0 days is refused');
select t.err($$update public.ledgers set last_reminded_at = now() where id = (select v from t.ids where k = 'L_B')$$,
             '42501', 'last_reminded_at is not written directly');
select t.ok(public.mark_reminded((select v from t.ids where k = 'L_B')) is not null, 'the owner marks a reminder sent');
select t.ok((select last_reminded_at from public.ledgers where id = (select v from t.ids where k = 'L_B'))
              between now() - interval '1 minute' and now(), 'it is stamped with the server time');
:as_B
update public.ledgers set remind_every_days = 1 where id = (select v from t.ids where k = 'L_B');
select t.err($$select public.mark_reminded((select v from t.ids where k = 'L_B'))$$,
             'P0002', 'the counterparty cannot mark a reminder');
:as_A
select t.ok((select remind_every_days from public.ledgers where id = (select v from t.ids where k = 'L_B')) = 7,
            'the counterparty cannot change the reminder period');
:as_anon
select t.err($$select public.mark_reminded((select v from t.ids where k = 'L_B'))$$,
             '42501', 'anon cannot mark a reminder');
reset role;

-- ================= 9. Send SMS hook (20261023000000) =================
create temp table t_hook (k text primary key, v jsonb);
grant all on t_hook to supabase_auth_admin;
set role supabase_auth_admin;
insert into t_hook select 'nokeys', public.send_sms_via_gateway(
  '{"user": {"phone": "967770827842"}, "sms": {"otp": "123456"}}');
reset role;
select t.ok((select v #>> '{error,http_code}' from t_hook where k = 'nokeys') = '500'
            and (select count(*) from net.sent) = 0,
            'without Vault credentials the hook refuses and sends nothing');
insert into vault.decrypted_secrets values ('sms_gate_username', 'gwuser'), ('sms_gate_password', 'gw:pass');
set role supabase_auth_admin;
insert into t_hook select 'ok', public.send_sms_via_gateway(
  '{"user": {"phone": "966500000009"}, "sms": {"otp": "654321", "phone": "967770827842"}}');
insert into t_hook select 'badphone', public.send_sms_via_gateway(
  '{"user": {"phone": "+12"}, "sms": {"otp": "654321"}}');
insert into t_hook select 'badotp', public.send_sms_via_gateway(
  '{"user": {"phone": "967770827842"}, "sms": {"otp": "12a"}}');
reset role;
select t.ok((select v from t_hook where k = 'ok') = '{}'::jsonb, 'the hook answers {} once queued');
select t.ok((select count(*) from net.sent) = 1, 'one request, none for the bad inputs');
select t.ok((select url from net.sent) = 'https://api.sms-gate.app/3rdparty/v1/message',
            'to the gateway cloud');
select t.ok((select body -> 'phoneNumbers' from net.sent) = '["+967770827842"]'::jsonb,
            'to sms.phone (where Auth sends the code), with +');
select t.ok((select body #>> '{textMessage,text}' from net.sent) like '%654321%',
            'the message carries the code');
select t.ok((select headers ->> 'Authorization' from net.sent)
              = 'Basic ' || encode(convert_to('gwuser:gw:pass', 'UTF8'), 'base64'),
            'basic auth from the Vault credentials');
select t.ok((select v #>> '{error,http_code}' from t_hook where k = 'badphone') = '400'
            and (select v #>> '{error,http_code}' from t_hook where k = 'badotp') = '400',
            'a bad phone or code is refused');
:as_A
select t.err($$select public.send_sms_via_gateway('{}')$$, '42501', 'users cannot call the hook');
:as_anon
select t.err($$select public.send_sms_via_gateway('{}')$$, '42501', 'anon cannot call the hook');
reset role;

-- ================= 10. deleting an account (20261024000000) =================
insert into auth.users values ('eeeeeeee-0000-0000-0000-000000000005', '966500000005', now());
\set as_E 'reset role; set request.jwt.claims to ''{"sub":"eeeeeeee-0000-0000-0000-000000000005"}''; set role authenticated;'
:as_E
insert into public.profiles (id, full_name) values (auth.uid(), 'Ezz');
insert into public.ledgers (counterparty_name, counterparty_phone) values ('Ahmed', '966500000001');
insert into t.ids select 'L_E', id from public.ledgers where owner_id = auth.uid();
insert into public.entries (ledger_id, direction, amount_minor) select v, 'out', 100 from t.ids where k = 'L_E';
:as_A
insert into public.ledgers (counterparty_name, counterparty_phone) values ('Ezz', '966500000005');
insert into t.ids select 'L_AE', id from public.ledgers where counterparty_phone = '966500000005';
:as_E
select public.link_my_ledgers();
insert into public.entries (ledger_id, direction, amount_minor, note) select v, 'in', 700, 'X1' from t.ids where k = 'L_AE';
insert into public.entries (ledger_id, direction, amount_minor, note) select v, 'in', 300, 'X2' from t.ids where k = 'L_AE';
insert into t.ids select note, id from public.entries where note in ('X1', 'X2');
:as_A
select public.respond_entry((select v from t.ids where k = 'X1'), 'confirmed');
insert into t.tokens select 'AE', public.create_share_link((select v from t.ids where k = 'L_AE'));
:as_anon
select t.err($$select public.delete_my_account()$$, '42501', 'anon cannot delete an account');
:as_E
select public.delete_my_account();
reset role;
select t.ok(not exists (select 1 from auth.users where id = 'eeeeeeee-0000-0000-0000-000000000005')
            and not exists (select 1 from public.profiles where id = 'eeeeeeee-0000-0000-0000-000000000005'),
            'the user and the profile are gone');
select t.ok(not exists (select 1 from public.ledgers where id = (select v from t.ids where k = 'L_E'))
            and not exists (select 1 from public.entries where ledger_id = (select v from t.ids where k = 'L_E')),
            'the ledgers E owned and their entries are gone');
select t.ok((select counterparty_id from public.ledgers where id = (select v from t.ids where k = 'L_AE')) is null,
            'A''s ledger with E stays, unlinked');
select t.ok((select count(*) from public.entries where ledger_id = (select v from t.ids where k = 'L_AE')
              and created_by is null) = 2,
            'the entries E recorded in it stay, with no author');
select t.ok((select confirmed_balance_minor from public.ledger_balances
              where ledger_id = (select v from t.ids where k = 'L_AE')) = -700,
            'A''s agreed balance does not move');
:as_anon
select t.err($$select public.respond_by_token((select v from t.tokens where k = 'AE'), (select v from t.ids where k = 'X2'), 'confirmed')$$,
             'P0002', 'a link cannot answer an entry with no author');
:as_A
select t.err($$select public.void_entry((select v from t.ids where k = 'X2'))$$,
             'P0002', 'nobody can withdraw an entry with no author');
select t.ok(public.respond_entry((select v from t.ids where k = 'X2'), 'confirmed') = 'confirmed',
            'the owner can still confirm it');
reset role;

-- ================= 11. the day of an entry (20261025000000) =================
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note, occurred_on)
  select v, 'out', 100, 'D1', current_date - 30 from t.ids where k = 'L_B';
select t.ok((select occurred_on from public.entries where note = 'D1') = current_date - 30,
            'an entry keeps an earlier day');
insert into public.entries (ledger_id, direction, amount_minor, note, occurred_on)
  select v, 'out', 100, 'D2', current_date + 1 from t.ids where k = 'L_B';
select t.ok(exists (select 1 from public.entries where note = 'D2'),
            'tomorrow is accepted (the app''s day runs ahead of UTC)');
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, occurred_on)
               select v, 'out', 100, current_date + 2 from t.ids where k = 'L_B'$$,
             '22023', 'a day after tomorrow is refused');
:as_B
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, occurred_on)
               select v, 'in', 100, current_date + 30 from t.ids where k = 'L_B'$$,
             '22023', 'the counterparty cannot date one in the future either');
select t.err($$update public.entries set occurred_on = current_date - 1 where note = 'D1'$$,
             '42501', 'the day cannot be changed afterwards');
reset role;

-- ================= 12. the repayment day (20261026000000) =================
:as_A
update public.ledgers set due_on = current_date + 10 where id = (select v from t.ids where k = 'L_B');
select t.ok((select due_on from public.ledgers where id = (select v from t.ids where k = 'L_B')) = current_date + 10,
            'the owner sets a repayment day');
:as_B
select t.ok((select due_on from public.ledgers where id = (select v from t.ids where k = 'L_B')) = current_date + 10,
            'the counterparty sees it');
update public.ledgers set due_on = current_date + 99 where id = (select v from t.ids where k = 'L_B');
reset role;
select t.ok((select due_on from public.ledgers where id = (select v from t.ids where k = 'L_B')) = current_date + 10,
            'the counterparty cannot move it');
:as_A
update public.ledgers set due_on = null where id = (select v from t.ids where k = 'L_B');
select t.ok((select due_on from public.ledgers where id = (select v from t.ids where k = 'L_B')) is null,
            'the owner clears it');
:as_anon
select t.err($$update public.ledgers set due_on = current_date$$, '42501', 'anon cannot set a repayment day');
reset role;

-- ================= 13. payments (20261027000000) =================
-- A new shop ledger between A and B: B owes A 100.00 on agreed entries.
:as_A
insert into public.businesses (name) values ('Pay shop');
insert into public.ledgers (business_id, counterparty_name, counterparty_phone)
  select id, 'Badr', '966500000002' from public.businesses where name = 'Pay shop';
insert into t.ids select 'L_P', l.id from public.ledgers l
  join public.businesses b on b.id = l.business_id where b.name = 'Pay shop';
:as_B
select public.link_my_ledgers();
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 10000, 'P-debt' from t.ids where k = 'L_P';
:as_B
select public.respond_entry((select id from public.entries where note = 'P-debt'), 'confirmed');
select t.ok((select kind from public.entries where note = 'P-debt') = 'debt', 'an entry is a debt by default');
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, kind)
               select v, 'in', 10001, 'payment' from t.ids where k = 'L_P'$$,
             '23514', 'a payment above what is owed is refused');
insert into public.entries (ledger_id, direction, amount_minor, note, kind)
  select v, 'in', 6000, 'P1', 'payment' from t.ids where k = 'L_P';
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, kind)
               select v, 'in', 4001, 'payment' from t.ids where k = 'L_P'$$,
             '23514', 'a pending payment holds its amount');
:as_A
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, kind)
               select v, 'out', 1, 'payment' from t.ids where k = 'L_P'$$,
             '23514', 'the side that owes nothing cannot pay');
-- the creditor records the rest as received
insert into public.entries (ledger_id, direction, amount_minor, note, kind)
  select v, 'in', 4000, 'P2', 'payment' from t.ids where k = 'L_P';
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, kind)
               select v, 'in', 1, 'payment' from t.ids where k = 'L_P'$$,
             '23514', 'nothing is left to pay');
:as_B
select public.respond_entry((select id from public.entries where note = 'P2'), 'disputed', 'not received');
:as_A
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, kind)
               select v, 'in', 1, 'payment' from t.ids where k = 'L_P'$$,
             '23514', 'a disputed payment still holds its amount');
select public.respond_entry((select id from public.entries where note = 'P1'), 'confirmed');
select t.ok((select confirmed_balance_minor from public.ledger_balances
              where ledger_id = (select v from t.ids where k = 'L_P')) = 4000,
            'a confirmed payment lowers the agreed balance');
select public.void_entry((select id from public.entries where note = 'P2'));
:as_B
insert into public.entries (ledger_id, direction, amount_minor, note, kind)
  select v, 'in', 4000, 'P3', 'payment' from t.ids where k = 'L_P';
select t.ok(exists (select 1 from public.entries where note = 'P3'), 'a withdrawn payment frees its amount');
select t.err($$update public.entries set kind = 'debt' where note = 'P3'$$,
             '42501', 'the kind cannot change afterwards');
-- the id made by the app: sent twice, saved once
insert into public.entries (id, ledger_id, direction, amount_minor, note)
  select '11111111-0000-4000-8000-000000000001', v, 'out', 100, 'ID1' from t.ids where k = 'L_P';
select t.err($$insert into public.entries (id, ledger_id, direction, amount_minor, note)
               select '11111111-0000-4000-8000-000000000001', v, 'out', 100, 'ID1' from t.ids where k = 'L_P'$$,
             '23505', 'the same id sent again is refused');
select t.ok((select count(*) from public.entries where note = 'ID1') = 1, 'and saved once');
reset role;

-- ================= 14. the audit trail (20261028000000) =================
create function t.trail(p_note text) returns text language sql as $$
  select string_agg(ev.event || ':' ||
                    case when ev.actor is null then '-'
                         when ev.actor = 'aaaaaaaa-0000-0000-0000-000000000001' then 'A'
                         when ev.actor = 'bbbbbbbb-0000-0000-0000-000000000002' then 'B'
                         else '?' end || ':' || coalesce(ev.via, '-') ||
                    coalesce(':' || ev.note, ''), ' ' order by ev.id)
    from public.entry_events ev join public.entries e on e.id = ev.entry_id
   where e.note = p_note
$$;
grant execute on function t.trail(text) to anon, authenticated;
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 500, 'EV1' from t.ids where k = 'L_P';
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 500, 'EV2' from t.ids where k = 'L_P';
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 500, 'EV3' from t.ids where k = 'L_P';
insert into t.tokens select 'P', public.create_share_link((select v from t.ids where k = 'L_P'));
insert into t.ids select 'EV3', id from public.entries where note = 'EV3';
:as_B
select public.respond_entry((select id from public.entries where note = 'EV1'), 'confirmed');
select public.respond_entry((select id from public.entries where note = 'EV2'), 'disputed', 'not mine');
:as_A
select public.void_entry((select id from public.entries where note = 'EV2'));
:as_anon
select public.respond_by_token((select v from t.tokens where k = 'P'),
                               (select v from t.ids where k = 'EV3'), 'confirmed');
:as_A
select t.ok(t.trail('EV1') = 'created:A:app confirmed:B:app', 'created by A, confirmed by B in the app');
select t.ok(t.trail('EV2') = 'created:A:app disputed:B:app:not mine voided:A:app',
            'a dispute keeps its reason, then the withdrawal');
select t.ok(t.trail('EV3') = 'created:A:app confirmed:-:link', 'an answer through the link has no account');
select t.ok(t.trail('P1') = 'created:B:app confirmed:A:app', 'a payment has its trail too');
:as_B
select t.ok(t.trail('EV1') = 'created:A:app confirmed:B:app', 'the other side reads the same trail');
:as_C
select t.ok(not exists (select 1 from public.entry_events
                         where ledger_id = (select v from t.ids where k = 'L_P')),
            'someone outside the ledger reads none of it');
:as_A
select t.err($$insert into public.entry_events (entry_id, ledger_id, event)
               select id, ledger_id, 'confirmed' from public.entries where note = 'EV1'$$,
             '42501', 'no one writes the trail by hand');
select t.err($$update public.entry_events set actor = null$$, '42501', 'or changes it');
select t.err($$delete from public.entry_events$$, '42501', 'or deletes from it');
:as_anon
select t.err($$select count(*) from public.entry_events$$, '42501', 'anon cannot read it');
reset role;

-- ================= 15. nothing financial can be forged from the client =================
-- An entry starts pending, by me, unanswered; afterwards only the functions
-- move its status, and nothing else about it changes.
:as_B
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, status)
               select v, 'in', 100, 'confirmed' from t.ids where k = 'L_P'$$,
             '42501', 'an entry cannot be born confirmed');
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, created_by)
               select v, 'in', 100, 'aaaaaaaa-0000-0000-0000-000000000001' from t.ids where k = 'L_P'$$,
             '42501', 'or recorded in the other side''s name');
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, responded_at, responded_via)
               select v, 'in', 100, now(), 'app' from t.ids where k = 'L_P'$$,
             '42501', 'or carry an answer');
select t.err($$update public.entries set amount_minor = 1 where note = 'P3'$$,
             '42501', 'the amount cannot change afterwards');
select t.err($$update public.entries set ledger_id = ledger_id where note = 'P3'$$,
             '42501', 'nor the ledger');
select t.err($$update public.entries set direction = 'out' where note = 'P3'$$,
             '42501', 'nor the direction');
select t.err($$delete from public.entries where note = 'P3'$$,
             '42501', 'an entry is never deleted by hand');
select t.err($$insert into public.ledger_balances (ledger_id) select v from t.ids where k = 'L_P'$$,
             '55000', 'balances are computed, never written (a view)');
:as_C
select t.err($$insert into public.entries (ledger_id, direction, amount_minor, kind)
               select v, 'in', 100, 'payment' from t.ids where k = 'L_P'$$,
             '42501', 'an outsider cannot pay into a ledger');
reset role;

-- ================= 16. the dashboard's flows (20261029000000) =================
-- A new shop ledger between A and B: B owes A 100.00, pays 30.00 forty days
-- ago and 20.00 + 5.00 today (all confirmed), then 10.00 still pending; A
-- records 7.00 pending and 5.00 that B disputes; one more is withdrawn.
create function t.flows(p_key text) returns text language sql as $$
  select coalesce(string_agg(f.status || ':' || f.direction || ':' ||
                             coalesce((f.paid_on - current_date)::text, '-') || ':' ||
                             f.amount_minor || ':' || f.entry_count, ' '
                             order by f.status, f.direction, f.paid_on), '')
    from public.ledger_flows f
   where f.ledger_id = (select v from t.ids where k = p_key)
$$;
grant execute on function t.flows(text) to anon, authenticated;
:as_A
insert into public.businesses (name) values ('Flow shop');
insert into public.ledgers (business_id, counterparty_name, counterparty_phone)
  select id, 'Badr', '966500000002' from public.businesses where name = 'Flow shop';
insert into t.ids select 'L_F', l.id from public.ledgers l
  join public.businesses b on b.id = l.business_id where b.name = 'Flow shop';
:as_B
select public.link_my_ledgers();
:as_A
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 10000, 'F-debt' from t.ids where k = 'L_F';
:as_B
select public.respond_entry((select id from public.entries where note = 'F-debt'), 'confirmed');
insert into public.entries (ledger_id, direction, amount_minor, note, kind, occurred_on)
  select v, 'in', 3000, 'F-pay1', 'payment', current_date - 40 from t.ids where k = 'L_F';
insert into public.entries (ledger_id, direction, amount_minor, note, kind)
  select v, 'in', 2000, 'F-pay2', 'payment' from t.ids where k = 'L_F';
insert into public.entries (ledger_id, direction, amount_minor, note, kind)
  select v, 'in', 500, 'F-pay3', 'payment' from t.ids where k = 'L_F';
:as_A
select public.respond_entry((select id from public.entries where note = 'F-pay1'), 'confirmed');
select public.respond_entry((select id from public.entries where note = 'F-pay2'), 'confirmed');
select public.respond_entry((select id from public.entries where note = 'F-pay3'), 'confirmed');
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 700, 'F-pend' from t.ids where k = 'L_F';
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 500, 'F-disp' from t.ids where k = 'L_F';
insert into public.entries (ledger_id, direction, amount_minor, note)
  select v, 'out', 900, 'F-void' from t.ids where k = 'L_F';
select public.void_entry((select id from public.entries where note = 'F-void'));
:as_B
insert into public.entries (ledger_id, direction, amount_minor, note, kind)
  select v, 'in', 1000, 'F-pay4', 'payment' from t.ids where k = 'L_F';
select public.respond_entry((select id from public.entries where note = 'F-disp'), 'disputed', 'not mine');
:as_A
select t.ok(t.flows('L_F') = 'pending:out:-:700:1 pending:in:-:1000:1 confirmed:in:-40:3000:1 '
                             'confirmed:in:0:2500:2 disputed:out:-:500:1',
            'flows: confirmed payments by day, pending and disputed apart');
select t.ok(not exists (select 1 from public.ledger_flows f
                         where f.ledger_id = (select v from t.ids where k = 'L_F')
                           and f.status = 'confirmed' and f.direction = 'out'),
            'a confirmed debt is not a flow');
select t.ok(not exists (select 1 from public.ledger_flows where status = 'voided'),
            'a withdrawn entry is not a flow');
:as_B
select t.ok(t.flows('L_F') = 'pending:out:-:700:1 pending:in:-:1000:1 confirmed:in:-40:3000:1 '
                             'confirmed:in:0:2500:2 disputed:out:-:500:1',
            'the other side reads the same flows');
select t.ok(not exists (select 1 from public.ledger_flows
                         where ledger_id = (select v from t.ids where k = 'L_C')),
            'and none of a ledger it is not in');
:as_C
select t.ok(t.flows('L_F') = '', 'someone outside the ledger reads none of it');
:as_D
select t.ok(not exists (select 1 from public.ledger_flows), 'an unlinked phone reads nothing');
:as_anon
select t.err($$select count(*) from public.ledger_flows$$, '42501', 'anon cannot read the flows');
:as_A
select t.err($$insert into public.ledger_flows (ledger_id) select v from t.ids where k = 'L_F'$$,
             '55000', 'flows are computed, never written (a view)');
reset role;
select t.ok((select reloptions from pg_class where oid = 'public.ledger_flows'::regclass)
              @> array['security_invoker=true'],
            'the flows view runs with the reader''s rights');

\echo ALL TESTS PASSED
