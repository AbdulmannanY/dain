// Dain share page: what an owner's share link opens. The other party reads
// the ledger and confirms or disputes the owner's entries without the app.
// No dependencies and no build step; share/dain-share.test.mjs runs the
// logic under `node --test`.
//
// Contract (supabase/migrations, checked live by the app's test/live):
//   get_shared_ledger(p_token) -> { owner_name, counterparty_name, currency,
//     confirmed_balance_minor, entries: [{ id, direction, amount_minor, note,
//     occurred_on, status, can_respond }] }, newest first, voided left out.
//   respond_by_token(p_token, p_entry_id, p_decision, p_note) -> status.
// Amounts are relative to the OWNER; this page shows the visitor's side.

export const SUPABASE_URL = 'https://mxnjwaofjlxxdjizjsfb.supabase.co';
// Publishable by design: RLS and the two functions guard the data.
export const SUPABASE_KEY = 'sb_publishable_JTVwmwscU9kAwi3PM2EQMQ_shfAYx5X';

/** The token after '#', or null when it cannot be one (24 bytes, base64url). */
export function tokenFromHash(hash) {
  const t = String(hash || '').replace(/^#/, '');
  return /^[A-Za-z0-9_-]{32}$/.test(t) ? t : null;
}

/** Same as the app's currencySymbol: an unknown code shows as itself. */
export function currencySymbol(currency) {
  return { SAR: 'ر.س', YER: 'ر.ي', USD: '$' }[currency] || currency;
}

/** Same as the app's formatMoney: 4550 -> '45.50 ر.س', 500000 -> '5,000 ر.ي'. */
export function formatMoney(minor, currency) {
  const abs = Math.abs(minor);
  const whole = Math.floor(abs / 100);
  const cents = abs % 100;
  let text = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  if (cents !== 0) text += '.' + String(cents).padStart(2, '0');
  return `${text} ${currencySymbol(currency)}`;
}

export function sideLabel(minor) {
  return minor > 0 ? 'لك' : minor < 0 ? 'عليك' : 'لا رصيد';
}

/** The ledger from the visitor's (counterparty's) side. */
export function viewOf(data) {
  return {
    title: data.owner_name,
    name: data.counterparty_name,
    currency: data.currency,
    // > 0 means the visitor owes the owner, so it flips for the visitor.
    balance: -data.confirmed_balance_minor,
    entries: (data.entries || []).map((e) => {
      const open = e.status === 'pending' || e.status === 'disputed';
      return {
        id: e.id,
        // 'out' = the owner gave the visitor: the visitor took.
        myDelta: (e.direction === 'out' ? -1 : 1) * e.amount_minor,
        note: e.note,
        day: e.occurred_on,
        status: e.status,
        canConfirm: Boolean(e.can_respond) && open,
        canDispute: Boolean(e.can_respond) && e.status === 'pending',
        payment: e.kind === 'payment',
      };
    }),
  };
}

/** As in the app: a payment reads "سدّدت" / "استلمت سداداً" from my side. */
export function entryTitle(e, currency) {
  const verb = e.payment
    ? (e.myDelta > 0 ? 'سدّدت' : 'استلمت سداداً')
    : (e.myDelta > 0 ? 'أعطيت' : 'أخذت');
  return `${verb} ${formatMoney(e.myDelta, currency)}`;
}

export function entryDetails(e) {
  const [y, m, d] = String(e.day).split('-').map(Number);
  const status = {
    pending: e.canConfirm ? 'بانتظار تأكيدك' : 'بانتظار التأكيد',
    confirmed: 'مؤكد',
    disputed: 'معترض عليه',
  }[e.status] || e.status;
  return [e.note, `${d}/${m}/${y}`, status].filter(Boolean).join(' · ');
}

export const REASON_ERROR = 'اكتب سبب الاعتراض (حتى 200 حرف).';

/** A dispute needs a reason, as in the app: 1..200 characters. */
export function checkReason(text) {
  const t = String(text || '').trim();
  const n = [...t].length;
  return n >= 1 && n <= 200 ? { reason: t } : { error: REASON_ERROR };
}

export function errorMessage(err) {
  switch (err && err.code) {
    case 'P0002':
      return 'الرابط غير صالح أو انتهت صلاحيته. اطلب من صاحب الدفتر رابطاً جديداً.';
    case '55000':
      return 'تغيّرت حالة هذا القيد. أُعيد تحميل الدفتر.';
    case 'network':
      return 'لا يوجد اتصال بالإنترنت.';
    default:
      return 'تعذّر إتمام العملية. حاول مجدداً.';
  }
}

/** POST /rest/v1/rpc/<name>; throws { code } like PostgREST errors. */
export async function rpc(name, params, fetchImpl) {
  let res;
  try {
    res = await fetchImpl(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(params),
    });
  } catch (_) {
    throw { code: 'network' };
  }
  const body = await res.json().catch(() => null);
  if (!res.ok) throw { code: (body && body.code) || String(res.status) };
  return body;
}

/** 22/10/2026, as the app shows a day. */
export function shortDay(date) {
  return `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`;
}

/**
 * The page's state and actions; [draw] is called after every change.
 * state.phase: 'loading' | 'error' | 'ready'. [print] opens the browser's
 * print dialog (a printer, or "Save as PDF"); [now] dates the statement.
 */
export function createApp({ token, fetchImpl, draw = () => {}, print = () => {}, now = () => new Date() }) {
  const state = {
    phase: 'loading',
    error: null,
    fatal: false,
    view: null,
    busy: false,
    notice: null,
    disputing: null,
    draft: '',
    formError: null,
    asOf: null,
  };
  const call = (name, params) => rpc(name, { p_token: token, ...params }, fetchImpl);

  async function load() {
    if (!token) {
      Object.assign(state, { phase: 'error', fatal: true, error: errorMessage({ code: 'P0002' }) });
      return draw(state);
    }
    if (!state.view) state.phase = 'loading';
    draw(state);
    try {
      state.view = viewOf(await call('get_shared_ledger', {}));
      state.asOf = shortDay(now());
      state.phase = 'ready';
      state.error = null;
    } catch (err) {
      state.error = errorMessage(err);
      state.fatal = err.code === 'P0002';
      if (state.fatal) state.view = null;
      state.phase = state.view && !state.fatal ? 'ready' : 'error';
    }
    draw(state);
  }

  async function respond(id, decision, note) {
    if (state.busy) return false;
    state.busy = true;
    state.notice = null;
    state.formError = null;
    draw(state);
    let ok = false;
    try {
      await call('respond_by_token', {
        p_entry_id: id,
        p_decision: decision,
        p_note: note ?? null,
      });
      ok = true;
      state.disputing = null;
      state.notice = decision === 'confirmed' ? 'أُكّد القيد.' : 'أُرسل الاعتراض.';
    } catch (err) {
      state.formError = errorMessage(err);
      if (err.code === '55000' || err.code === 'P0002') state.disputing = null;
    }
    state.busy = false;
    await load();
    return ok;
  }

  return {
    state,
    load,
    print,
    confirm: (id) => respond(id, 'confirmed'),
    startDispute(id) {
      state.disputing = id;
      state.draft = '';
      state.formError = null;
      draw(state);
    },
    /** Typing the reason does not redraw, so the field keeps its caret. */
    setDraft(text) {
      state.draft = text;
    },
    cancelDispute() {
      state.disputing = null;
      state.formError = null;
      draw(state);
    },
    async sendDispute(id, text) {
      const { reason, error } = checkReason(text);
      if (error) {
        state.formError = error;
        draw(state);
        return false;
      }
      return respond(id, 'disputed', reason);
    },
  };
}

/** A virtual node: rendering is a pure function of the state. */
export function h(tag, props, ...children) {
  return { tag, props: props || {}, children: children.flat().filter((c) => c != null && c !== false) };
}

export function view(state, act) {
  const page = (...body) => h('div', { class: 'page' }, h('header', null, h('h1', null, 'دائن')), ...body);
  if (state.phase === 'loading') return page(h('p', { class: 'muted' }, 'جارٍ التحميل…'));
  if (state.phase === 'error') {
    return page(
      h('p', { class: 'error', 'data-key': 'error' }, state.error),
      !state.fatal && h('button', { 'data-key': 'retry', onclick: () => act.load() }, 'إعادة المحاولة'),
    );
  }
  const v = state.view;
  const busy = state.busy;
  const entry = (e) => {
    const disputing = state.disputing === e.id;
    return h(
      'li',
      { 'data-key': `entry-${e.id}` },
      h('div', { class: 'entry-title' }, entryTitle(e, v.currency)),
      h('div', { class: 'muted' }, entryDetails(e)),
      disputing
        ? h(
            'div',
            { class: 'dispute' },
            h('textarea', {
              id: 'reason',
              'data-key': 'reason',
              maxlength: '200',
              placeholder: 'سبب الاعتراض',
              value: state.draft,
              oninput: (ev) => act.setDraft(ev.target.value),
            }),
            state.formError && h('p', { class: 'error', 'data-key': 'form-error' }, state.formError),
            h('button', { 'data-key': 'send-dispute', disabled: busy, onclick: () => act.sendDispute(e.id, state.draft) }, 'إرسال الاعتراض'),
            h('button', { class: 'secondary', 'data-key': 'cancel-dispute', disabled: busy, onclick: () => act.cancelDispute() }, 'إلغاء'),
          )
        : (e.canConfirm || e.canDispute) &&
            h(
              'div',
              { class: 'actions' },
              e.canConfirm && h('button', { 'data-key': `confirm-${e.id}`, disabled: busy, onclick: () => act.confirm(e.id) }, 'تأكيد'),
              e.canDispute && h('button', { class: 'secondary', 'data-key': `dispute-${e.id}`, disabled: busy, onclick: () => act.startDispute(e.id) }, 'اعتراض'),
            ),
    );
  };
  return page(
    h('h2', null, `دفترك مع ${v.title}`),
    // On paper the page is a statement: who, and as of which day.
    state.asOf && h('p', { class: 'print-only', 'data-key': 'statement' }, `كشف حساب ${v.name} حتى ${state.asOf}`),
    h('p', { class: 'muted no-print' }, `أهلاً ${v.name}. هذه القيود سجّلها ${v.title}، وتستطيع تأكيدها أو الاعتراض عليها.`),
    h(
      'section',
      { class: 'balance', 'data-key': 'balance' },
      h('div', null, sideLabel(v.balance)),
      v.balance !== 0 && h('div', { class: 'amount' }, formatMoney(v.balance, v.currency)),
      h('div', { class: 'muted' }, 'الرصيد المتفق عليه (المؤكد فقط).'),
    ),
    h('button', { class: 'secondary', 'data-key': 'print', onclick: () => act.print() }, 'طباعة الكشف أو حفظه PDF'),
    state.notice && h('p', { class: 'notice', 'data-key': 'notice' }, state.notice),
    state.error && h('p', { class: 'error', 'data-key': 'error' }, state.error),
    state.formError && !state.disputing && h('p', { class: 'error', 'data-key': 'form-error' }, state.formError),
    v.entries.length === 0
      ? h('p', { class: 'muted', 'data-key': 'empty' }, 'لا قيود بعد.')
      : h('ul', { class: 'entries' }, v.entries.map(entry)),
    h('p', { class: 'muted no-print' }, h('a', { href: 'privacy.html', 'data-key': 'privacy' }, 'سياسة الخصوصية')),
  );
}

/** Builds real DOM from a virtual node. Text goes through textContent only. */
export function mount(root, node, doc) {
  const build = (n) => {
    if (typeof n === 'string' || typeof n === 'number') return doc.createTextNode(String(n));
    const el = doc.createElement(n.tag);
    for (const [k, val] of Object.entries(n.props)) {
      if (k === 'onclick') el.addEventListener('click', val);
      else if (k === 'oninput') el.addEventListener('input', val);
      else if (k === 'value') el.value = val;
      else if (k === 'disabled') el.disabled = Boolean(val);
      else el.setAttribute(k, val);
    }
    for (const c of n.children) el.appendChild(build(c));
    return el;
  };
  root.replaceChildren(build(node));
}

/** Browser entry point: reads the token from the URL fragment. */
export function start(root, win) {
  const doc = win.document;
  let app;
  const draw = (state) => {
    mount(root, view(state, app), doc);
    if (state.disputing) doc.getElementById('reason')?.focus();
  };
  const boot = () => {
    app = createApp({
      token: tokenFromHash(win.location.hash),
      fetchImpl: win.fetch.bind(win),
      draw,
      print: () => win.print(),
    });
    return app.load();
  };
  win.addEventListener('hashchange', boot);
  return boot();
}

if (typeof window !== 'undefined' && window.document) {
  start(window.document.getElementById('app'), window);
}
