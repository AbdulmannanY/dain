// node --test share/dain-share.test.mjs  (no dependencies)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  REASON_ERROR,
  SUPABASE_KEY,
  SUPABASE_URL,
  checkReason,
  createApp,
  entryDetails,
  entryTitle,
  errorMessage,
  formatMoney,
  mount,
  tokenFromHash,
  view,
  viewOf,
} from './dain-share.js';

const TOKEN = 'abcdefghijklmnopqrstuvwxyzAB-_09';

// The shape get_shared_ledger returns (asserted live in app/test/live).
const ledger = (entries, balance = 0) => ({
  owner_name: 'بقالة النور',
  counterparty_name: 'سعد',
  currency: 'SAR',
  confirmed_balance_minor: balance,
  entries,
});
const row = (id, direction, amount, status, canRespond, note = null) => ({
  id,
  direction,
  amount_minor: amount,
  note,
  occurred_on: '2026-10-21',
  status,
  can_respond: canRespond,
});

/** A fetch that answers RPCs from [handlers] and records every call. */
function fakeFetch(handlers) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    const name = url.split('/rpc/')[1];
    const params = JSON.parse(init.body);
    calls.push({ url, name, params, headers: init.headers, method: init.method });
    const out = await handlers[name](params);
    if (out instanceof Error) throw out; // network failure
    const [status, body] = out;
    return { ok: status < 300, status, json: async () => body };
  };
  return { fetchImpl, calls };
}

/** Every string under a virtual node, with data-keys, for assertions. */
function texts(node) {
  if (typeof node === 'string') return [node];
  return node.children.flatMap(texts);
}
function find(node, key) {
  if (typeof node === 'string') return null;
  if (node.props['data-key'] === key) return node;
  for (const c of node.children) {
    const f = find(c, key);
    if (f) return f;
  }
  return null;
}

test('tokenFromHash accepts only a 32-character base64url token', () => {
  assert.equal(tokenFromHash('#' + TOKEN), TOKEN);
  assert.equal(tokenFromHash(TOKEN), TOKEN);
  for (const bad of ['', '#', '#short', '#' + TOKEN + 'x', '#' + TOKEN.slice(1) + '+', null]) {
    assert.equal(tokenFromHash(bad), null, String(bad));
  }
});

test('formatMoney matches the app', () => {
  assert.equal(formatMoney(4550, 'SAR'), '45.50 ر.س');
  assert.equal(formatMoney(-500000, 'SAR'), '5,000 ر.س');
  assert.equal(formatMoney(123456789, 'SAR'), '1,234,567.89 ر.س');
  assert.equal(formatMoney(100, 'USD'), '1 $');
  assert.equal(formatMoney(5000050, 'YER'), '50,000.50 ر.ي');
  assert.equal(formatMoney(100, 'EUR'), '1 EUR');
});

test('viewOf turns the owner-relative ledger to the visitor\'s side', () => {
  const v = viewOf(
    ledger(
      [
        row('a', 'out', 1250, 'pending', true, 'أرز'), // owner gave me
        row('b', 'in', 200, 'pending', false), // I gave the owner (my entry)
        row('c', 'out', 300, 'disputed', true),
        row('d', 'out', 400, 'confirmed', true),
      ],
      7000, // I owe the owner 70
    ),
  );
  assert.equal(v.title, 'بقالة النور');
  assert.equal(v.balance, -7000);
  assert.deepEqual(
    v.entries.map((e) => [e.id, e.myDelta, e.canConfirm, e.canDispute]),
    [
      ['a', -1250, true, true],
      ['b', 200, false, false],
      ['c', -300, true, false],
      ['d', -400, false, false],
    ],
  );
  assert.equal(entryTitle(v.entries[0], 'SAR'), 'أخذت 12.50 ر.س');
  assert.equal(entryTitle(v.entries[1], 'SAR'), 'أعطيت 2 ر.س');
  assert.equal(entryDetails(v.entries[0]), 'أرز · 21/10/2026 · بانتظار تأكيدك');
  assert.equal(entryDetails(v.entries[1]), '21/10/2026 · بانتظار التأكيد');
});

test('checkReason: 1..200 characters, trimmed', () => {
  assert.deepEqual(checkReason('  ليس لي '), { reason: 'ليس لي' });
  assert.deepEqual(checkReason('   '), { error: REASON_ERROR });
  assert.deepEqual(checkReason('ن'.repeat(201)), { error: REASON_ERROR });
  assert.deepEqual(checkReason('ن'.repeat(200)).reason.length, 200);
});

test('errorMessage per PostgREST code', () => {
  assert.match(errorMessage({ code: 'P0002' }), /الرابط غير صالح/);
  assert.match(errorMessage({ code: '55000' }), /تغيّرت حالة/);
  assert.equal(errorMessage({ code: 'network' }), 'لا يوجد اتصال بالإنترنت.');
  assert.match(errorMessage({ code: '500' }), /تعذّر/);
});

test('loads with the token and the publishable key, and draws the ledger', async () => {
  const { fetchImpl, calls } = fakeFetch({
    get_shared_ledger: () => [200, ledger([row('a', 'out', 1250, 'pending', true)], 1250)],
  });
  const draws = [];
  const app = createApp({ token: TOKEN, fetchImpl, draw: (s) => draws.push(s.phase) });
  await app.load();
  assert.deepEqual(draws, ['loading', 'ready']);
  assert.equal(calls[0].url, `${SUPABASE_URL}/rest/v1/rpc/get_shared_ledger`);
  assert.equal(calls[0].method, 'POST');
  assert.equal(calls[0].headers.apikey, SUPABASE_KEY);
  assert.deepEqual(calls[0].params, { p_token: TOKEN });

  const page = view(app.state, app);
  const all = texts(page);
  assert.ok(all.includes('دفترك مع بقالة النور'));
  assert.ok(all.includes('عليك'));
  assert.ok(all.includes('12.50 ر.س'));
  assert.ok(find(page, 'confirm-a'));
  assert.ok(find(page, 'dispute-a'));
});

test('a missing or wrong token ends on a message without a retry', async () => {
  const none = createApp({ token: null, fetchImpl: () => assert.fail('no call') });
  await none.load();
  assert.equal(none.state.phase, 'error');
  assert.equal(find(view(none.state, none), 'retry'), null);

  const { fetchImpl } = fakeFetch({ get_shared_ledger: () => [400, { code: 'P0002' }] });
  const wrong = createApp({ token: TOKEN, fetchImpl });
  await wrong.load();
  assert.equal(wrong.state.phase, 'error');
  assert.match(wrong.state.error, /الرابط غير صالح/);
  assert.equal(find(view(wrong.state, wrong), 'retry'), null);
});

test('a network failure offers a retry that loads', async () => {
  let online = false;
  const { fetchImpl } = fakeFetch({
    get_shared_ledger: () => (online ? [200, ledger([])] : new Error('offline')),
  });
  const app = createApp({ token: TOKEN, fetchImpl });
  await app.load();
  assert.equal(app.state.error, 'لا يوجد اتصال بالإنترنت.');
  assert.ok(find(view(app.state, app), 'retry'));
  online = true;
  await app.load();
  assert.equal(app.state.phase, 'ready');
  assert.ok(find(view(app.state, app), 'empty'));
});

test('confirm sends respond_by_token and reloads', async () => {
  let status = 'pending';
  const { fetchImpl, calls } = fakeFetch({
    get_shared_ledger: () => [200, ledger([row('a', 'out', 1250, status, true)])],
    respond_by_token: (p) => {
      status = p.p_decision;
      return [200, status];
    },
  });
  const app = createApp({ token: TOKEN, fetchImpl });
  await app.load();
  assert.equal(await app.confirm('a'), true);
  assert.deepEqual(calls[1].params, {
    p_token: TOKEN,
    p_entry_id: 'a',
    p_decision: 'confirmed',
    p_note: null,
  });
  assert.equal(calls[2].name, 'get_shared_ledger');
  assert.equal(app.state.notice, 'أُكّد القيد.');
  assert.equal(find(view(app.state, app), 'confirm-a'), null);
});

test('a dispute needs a reason; the reason is sent trimmed', async () => {
  const { fetchImpl, calls } = fakeFetch({
    get_shared_ledger: () => [200, ledger([row('a', 'out', 1250, 'pending', true)])],
    respond_by_token: () => [200, 'disputed'],
  });
  const app = createApp({ token: TOKEN, fetchImpl });
  await app.load();
  app.startDispute('a');
  let page = view(app.state, app);
  assert.ok(find(page, 'reason'));
  assert.equal(find(page, 'confirm-a'), null);

  assert.equal(await app.sendDispute('a', '  '), false);
  assert.equal(app.state.formError, REASON_ERROR);
  assert.equal(calls.length, 1);
  // The typed text survives a redraw.
  app.setDraft('المبلغ 10 لا 12.5');
  assert.equal(find(view(app.state, app), 'reason').props.value, 'المبلغ 10 لا 12.5');

  assert.equal(await app.sendDispute('a', ' المبلغ 10 لا 12.5 '), true);
  assert.equal(calls[1].params.p_decision, 'disputed');
  assert.equal(calls[1].params.p_note, 'المبلغ 10 لا 12.5');
  assert.equal(app.state.disputing, null);
  assert.equal(app.state.notice, 'أُرسل الاعتراض.');
});

test('if the owner acted first (55000), the page says so and reloads', async () => {
  let status = 'pending';
  const { fetchImpl, calls } = fakeFetch({
    get_shared_ledger: () => [200, ledger([row('a', 'out', 1250, status, true)])],
    respond_by_token: () => {
      status = 'confirmed';
      return [400, { code: '55000' }];
    },
  });
  const app = createApp({ token: TOKEN, fetchImpl });
  await app.load();
  app.startDispute('a');
  assert.equal(await app.sendDispute('a', 'سبب'), false);
  assert.match(app.state.formError, /تغيّرت حالة/);
  assert.equal(app.state.disputing, null);
  assert.equal(calls.at(-1).name, 'get_shared_ledger');
  const page = view(app.state, app);
  assert.ok(texts(page).includes('تغيّرت حالة هذا القيد. أُعيد تحميل الدفتر.'));
  assert.equal(find(page, 'confirm-a'), null);
});

test('the statement: a dated line for paper, and a button that prints', async () => {
  const { fetchImpl } = fakeFetch({
    get_shared_ledger: () => [200, ledger([row('a', 'out', 1250, 'confirmed', true)], 1250)],
  });
  let printed = 0;
  const app = createApp({
    token: TOKEN,
    fetchImpl,
    print: () => printed++,
    now: () => new Date(2026, 9, 22, 23, 59),
  });
  await app.load();
  const page = view(app.state, app);
  const line = find(page, 'statement');
  assert.deepEqual(texts(line), ['كشف حساب سعد حتى 22/10/2026']);
  assert.equal(line.props.class, 'print-only');
  find(page, 'print').props.onclick();
  assert.equal(printed, 1);
  assert.equal(find(page, 'privacy').props.href, 'privacy.html');
});

test('the privacy page: no script, a strict CSP, and it goes online', () => {
  const read = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
  const privacy = read('./privacy.html');
  assert.ok(!/<script/i.test(privacy), 'no script');
  assert.match(privacy, /content="default-src 'none';/);
  assert.match(privacy, /حذف الحساب/);
  assert.match(read('../.github/workflows/pages.yml'), /cp share\/index\.html share\/dain-share\.js share\/privacy\.html _site\//);
});

test('mount builds text nodes, never markup, and wires clicks', () => {
  // A minimal document: enough to see what mount() asks for.
  const made = [];
  const el = (tag) => {
    const node = { tag, attrs: {}, children: [], listeners: {}, value: undefined };
    node.setAttribute = (k, v) => (node.attrs[k] = v);
    node.appendChild = (c) => node.children.push(c);
    node.addEventListener = (type, fn) => (node.listeners[type] = fn);
    made.push(node);
    return node;
  };
  const doc = { createElement: el, createTextNode: (text) => ({ text }) };
  const root = { replaceChildren: (c) => (root.child = c) };
  let clicked = 0;

  const v = viewOf(ledger([row('a', 'out', 100, 'pending', true, '<img src=x onerror=alert(1)>')]));
  const app = { confirm: () => clicked++, startDispute: () => {} };
  mount(root, view({ phase: 'ready', view: v, disputing: null }, app), doc);

  assert.equal(root.child.tag, 'div');
  assert.ok(!made.some((n) => n.tag === 'img'), 'no element from the note');
  const all = (n) => (n.text !== undefined ? [n.text] : n.children.flatMap(all));
  assert.ok(all(root.child).some((t) => t.startsWith('<img')), 'the note is text');
  const confirm = made.find((n) => n.attrs['data-key'] === 'confirm-a');
  confirm.listeners.click();
  assert.equal(clicked, 1);
});
