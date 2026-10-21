// Live end-to-end check against the real Supabase project, through the same
// SessionController and Supabase repositories the app uses. Opt-in:
//
//   flutter test test/live --dart-define=DAIN_LIVE=true
//
// Uses the Supabase test numbers 966500000001 / 966500000002 (code 123456),
// so no SMS is sent. Profiles are created once; every run adds new shops,
// shop ledgers for B's phone and entries, so each run proves a fresh link
// and fresh balances.
@Tags(['live'])
library;

import 'dart:io';

import 'package:dain/core/config.dart';
import 'package:dain/data/auth_repository.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/data/profile_repository.dart';
import 'package:dain/ledgers/ledger_controller.dart';
import 'package:dain/ledgers/open_ledger_controller.dart';
import 'package:dain/ledgers/shops_controller.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _live = bool.fromEnvironment('DAIN_LIVE');
const _code = '123456';

/// Honours HTTPS_PROXY when the environment sets one; a direct connection
/// otherwise (Dart's HttpClient ignores proxy variables by default).
class _EnvProxyOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = HttpClient.findProxyFromEnvironment;
}

class _Session {
  _Session()
    : client = SupabaseClient(
        DainConfig.supabaseUrl,
        DainConfig.supabaseKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
          autoRefreshToken: false,
        ),
      ) {
    controller = SessionController(
      auth: SupabaseAuthRepository(client),
      profiles: SupabaseProfileRepository(client),
    );
  }

  final SupabaseClient client;
  late final SessionController controller;

  String get uid => client.auth.currentUser!.id;

  /// Phone -> code -> (profile) -> link_my_ledgers, exactly as the screens do.
  Future<void> signIn(String typedPhone, String name) async {
    final c = controller;
    await c.start();
    expect(c.stage, SessionStage.enterPhone);

    await c.requestCode(typedPhone);
    expect(c.error, isNull, reason: 'send OTP to $typedPhone');
    expect(c.stage, SessionStage.enterCode);

    await c.verifyCode(_code);
    expect(c.error, isNull, reason: 'verify OTP for $typedPhone');
    if (c.stage == SessionStage.needsProfile) {
      await c.createProfile(name);
      expect(c.error, isNull, reason: 'create profile');
    }
    expect(c.stage, SessionStage.ready);
    expect(c.profile?.id, uid);
    expect(c.linkedCount, isNotNull);
  }

  /// The next app launch: start() with the saved session runs
  /// link_my_ledgers() again, without a new OTP. Returns how many it linked.
  Future<int> relaunch() async {
    await controller.start();
    expect(controller.error, isNull, reason: 'relaunch');
    expect(controller.stage, SessionStage.ready);
    return controller.linkedCount!;
  }

  Future<void> close() async {
    await client.auth.signOut();
    await client.dispose();
  }
}

void main() {
  HttpOverrides.global = _EnvProxyOverrides();

  // Supabase refuses another OTP for the same phone inside its resend window
  // (over_sms_send_rate_limit), test numbers included. So each phone signs in
  // once per run, and later links come from relaunch().
  late _Session a;
  late _Session b;

  setUpAll(() async {
    if (!_live) return;
    a = _Session();
    b = _Session();
    await a.signIn('0500000001', 'تجربة أ');
    await b.signIn('+966 50 000 0002', 'تجربة ب');
  });

  tearDownAll(() async {
    if (!_live) return;
    await a.close();
    await b.close();
  });

  test(
    'A records a ledger for B\'s phone; B signs in and it is linked to B',
    () async {
      // Setup through RLS as A: a new shop and a ledger in it for B's phone.
      // A new (owner, business) pair each run, so the unique key never stops it.
      final shop = await a.client
          .from('businesses')
          .insert({'name': 'live ${DateTime.now().toUtc().toIso8601String()}'})
          .select('id')
          .single();
      final ledger = await a.client
          .from('ledgers')
          .insert({
            'business_id': shop['id'],
            'counterparty_name': 'تجربة ب',
            'counterparty_phone': '966500000002',
          })
          .select('id, counterparty_id')
          .single();
      expect(ledger['counterparty_id'], isNull);

      expect(await b.relaunch(), greaterThanOrEqualTo(1));

      // B can read the ledger only because link_my_ledgers() set
      // counterparty_id = B (ledgers_select policy).
      final linked = await b.client
          .from('ledgers')
          .select('id, owner_id, counterparty_id')
          .eq('id', ledger['id'] as String);
      expect(linked, hasLength(1));
      expect(linked.single['owner_id'], a.uid);
      expect(linked.single['counterparty_id'], b.uid);

      // Idempotent: nothing left to link.
      expect(await SupabaseProfileRepository(b.client).linkMyLedgers(), 0);

      // A never becomes its own counterparty.
      expect(await SupabaseProfileRepository(a.client).linkMyLedgers(), 0);
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the ledger list shows the agreed balance from each side',
    () async {
      final shopName = 'live list ${DateTime.now().toUtc().toIso8601String()}';
      final shop = await a.client
          .from('businesses')
          .insert({'name': shopName})
          .select('id')
          .single();
      final ledger = await a.client
          .from('ledgers')
          .insert({
            'business_id': shop['id'],
            'counterparty_name': 'تجربة ب',
            'counterparty_phone': '966500000002',
          })
          .select('id')
          .single();
      final ledgerId = ledger['id'] as String;

      // A sold B 123.45 SAR (B will confirm) and B paid 3.45 (left pending).
      final sale = await a.client
          .from('entries')
          .insert({
            'ledger_id': ledgerId,
            'direction': 'out',
            'amount_minor': 12345,
          })
          .select('id')
          .single();
      await a.client.from('entries').insert({
        'ledger_id': ledgerId,
        'direction': 'in',
        'amount_minor': 345,
      });

      expect(await b.relaunch(), greaterThanOrEqualTo(1));
      await b.client.rpc<dynamic>(
        'respond_entry',
        params: {'p_entry_id': sale['id'], 'p_decision': 'confirmed'},
      );

      // Owner's side: B owes A.
      final mine = await SupabaseLedgerRepository(a.client).fetchMine();
      final asOwner = mine.singleWhere((l) => l.id == ledgerId);
      expect(asOwner.iAmOwner, isTrue);
      expect(asOwner.title, 'تجربة ب');
      expect(asOwner.subtitle, shopName);
      expect(asOwner.otherPartyJoined, isTrue);
      expect(asOwner.myConfirmedMinor, 12345);
      expect(asOwner.myOpenMinor, 12000);
      expect(asOwner.pendingCount, 1);
      expect(asOwner.disputedCount, 0);

      // Counterparty's side: the same ledger, sign flipped, shop as title.
      final theirs = await SupabaseLedgerRepository(b.client).fetchMine();
      final asCounterparty = theirs.singleWhere((l) => l.id == ledgerId);
      expect(asCounterparty.iAmOwner, isFalse);
      expect(asCounterparty.title, shopName);
      expect(asCounterparty.subtitle, a.controller.profile!.fullName);
      expect(asCounterparty.myConfirmedMinor, -12345);
      expect(asCounterparty.myOpenMinor, -12000);
      expect(asCounterparty.pendingCount, 1);
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'A opens a ledger in a new shop from the form; B is linked to it',
    () async {
      final aLedgers = SupabaseLedgerRepository(a.client);
      expect(aLedgers.myPhone, '966500000001');

      final form = OpenLedgerController(aLedgers);
      addTearDown(form.dispose);
      await form.load();
      expect(form.error, isNull, reason: 'load my shops');

      // My own number is refused before anything is written.
      final shopsBefore = form.businesses!.length;
      form.select(const NewShopOwner());
      expect(
        await form.submit(
          name: 'أنا',
          phone: '+966 50 000 0001',
          newShopName: 'unused',
        ),
        isNull,
      );
      expect(form.error, 'هذا رقمك أنت. أدخل رقم الطرف الآخر.');
      expect(await aLedgers.fetchMyBusinesses(), hasLength(shopsBefore));

      // A new shop and a ledger in it for B's phone, as the screen does it.
      final shopName = 'live open ${DateTime.now().toUtc().toIso8601String()}';
      final ledgerId = await form.submit(
        name: 'تجربة ب',
        phone: '٠٥٠٠٠٠٠٠٠٢',
        newShopName: shopName,
      );
      expect(form.error, isNull, reason: 'open ledger');
      expect(ledgerId, isNotNull);
      final shop = (await aLedgers.fetchMyBusinesses()).singleWhere(
        (s) => s.name == shopName,
      );
      expect((form.owner as ShopOwner).businessId, shop.id);

      // The unique key (owner, shop, phone) refuses a second one.
      expect(await form.submit(name: 'تجربة ب', phone: '0500000002'), isNull);
      expect(form.error, 'لهذا الرقم دفتر في هذا المحل بالفعل.');

      final asOwner = (await aLedgers.fetchMine()).singleWhere(
        (l) => l.id == ledgerId,
      );
      expect(asOwner.title, 'تجربة ب');
      expect(asOwner.subtitle, shopName);
      expect(asOwner.otherPartyJoined, isFalse);

      expect(await b.relaunch(), greaterThanOrEqualTo(1));
      final bLedgers = SupabaseLedgerRepository(b.client);
      final asCounterparty = (await bLedgers.fetchMine()).singleWhere(
        (l) => l.id == ledgerId,
      );
      expect(asCounterparty.iAmOwner, isFalse);
      expect(asCounterparty.title, shopName);

      // RLS now shows A's shop to B, but it is not one of B's shops.
      expect(
        (await bLedgers.fetchMyBusinesses()).map((s) => s.id),
        isNot(contains(shop.id)),
      );
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'entries recorded from each side keep their meaning on both sides',
    () async {
      // Setup through RLS as A: a new shop ledger for B's phone, linked to B.
      final shop = await a.client
          .from('businesses')
          .insert({'name': 'live entries ${DateTime.now().toUtc()}'})
          .select('id')
          .single();
      final ledger = await a.client
          .from('ledgers')
          .insert({
            'business_id': shop['id'],
            'counterparty_name': 'تجربة ب',
            'counterparty_phone': '966500000002',
          })
          .select('id')
          .single();
      final ledgerId = ledger['id'] as String;
      expect(await b.relaunch(), greaterThanOrEqualTo(1));

      // The screens' controllers with the real repositories.
      final aView = LedgerController(
        SupabaseLedgerRepository(a.client),
        ledgerId,
      );
      final bView = LedgerController(
        SupabaseLedgerRepository(b.client),
        ledgerId,
      );
      addTearDown(aView.dispose);
      addTearDown(bView.dispose);
      await aView.load();
      await bView.load();
      expect(aView.error, isNull);
      expect(bView.error, isNull);
      expect(aView.ledger!.iAmOwner, isTrue);
      expect(bView.ledger!.iAmOwner, isFalse);

      // A (owner) gave 100.00; then B (counterparty) gave 30.00.
      expect(
        await aView.addEntry(iGave: true, amount: '100', note: 'live'),
        isTrue,
        reason: aView.formError,
      );
      expect(
        await bView.addEntry(iGave: true, amount: '٣٠'),
        isTrue,
        reason: bView.formError,
      );

      // Stored relative to the owner, each with its author and pending.
      final rows = await a.client
          .from('entries')
          .select('id, direction, amount_minor, status, note, created_by')
          .eq('ledger_id', ledgerId)
          .order('created_at', ascending: true);
      expect(
        rows.map(
          (r) => (
            r['direction'],
            r['amount_minor'],
            r['status'],
            r['note'],
            r['created_by'],
          ),
        ),
        [
          ('out', 10000, 'pending', 'live', a.uid),
          ('in', 3000, 'pending', null, b.uid),
        ],
      );

      // Pending only: the agreed balance is still zero on both sides.
      await aView.load();
      expect(aView.ledger!.myConfirmedMinor, 0);
      expect(aView.ledger!.myOpenMinor, 7000);
      expect(bView.ledger!.myOpenMinor, -7000);

      // Each side confirms the other's entry (the buttons come next).
      await b.client.rpc<dynamic>(
        'respond_entry',
        params: {'p_entry_id': rows[0]['id'], 'p_decision': 'confirmed'},
      );
      await a.client.rpc<dynamic>(
        'respond_entry',
        params: {'p_entry_id': rows[1]['id'], 'p_decision': 'confirmed'},
      );
      await aView.load();
      await bView.load();

      // B owes A 70.00, seen from each side; newest entry first.
      expect(aView.ledger!.myConfirmedMinor, 7000);
      expect(bView.ledger!.myConfirmedMinor, -7000);
      (int, bool, EntryStatus) view(LedgerEntry e) =>
          (e.myDeltaMinor, e.createdByMe, e.status);
      expect(aView.entries.map(view), [
        (-3000, false, EntryStatus.confirmed),
        (10000, true, EntryStatus.confirmed),
      ]);
      expect(bView.entries.map(view), [
        (3000, true, EntryStatus.confirmed),
        (-10000, false, EntryStatus.confirmed),
      ]);
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'confirm, dispute and withdraw through the screens\' controller',
    () async {
      // Setup through RLS as A: a new shop ledger for B's phone, linked to B.
      final shop = await a.client
          .from('businesses')
          .insert({'name': 'live respond ${DateTime.now().toUtc()}'})
          .select('id')
          .single();
      final ledger = await a.client
          .from('ledgers')
          .insert({
            'business_id': shop['id'],
            'counterparty_name': 'تجربة ب',
            'counterparty_phone': '966500000002',
          })
          .select('id')
          .single();
      final ledgerId = ledger['id'] as String;
      expect(await b.relaunch(), greaterThanOrEqualTo(1));

      final aView = LedgerController(
        SupabaseLedgerRepository(a.client),
        ledgerId,
      );
      final bView = LedgerController(
        SupabaseLedgerRepository(b.client),
        ledgerId,
      );
      addTearDown(aView.dispose);
      addTearDown(bView.dispose);
      await aView.load();
      expect(await aView.addEntry(iGave: true, amount: '50'), isTrue);
      expect(await aView.addEntry(iGave: true, amount: '20'), isTrue);
      await bView.load();
      final [second, first] = bView.entries; // newest first
      expect(entryActions(first), {EntryAction.confirm, EntryAction.dispute});
      expect(entryActions(aView.entries.last), {EntryAction.withdraw});

      // B disputes 50 with a reason; an empty reason never reaches the server.
      expect(await bView.disputeEntry(first.id, '  '), isFalse);
      expect(await bView.disputeEntry(first.id, ' ليس لي '), isTrue);
      final row = await a.client
          .from('entries')
          .select('status, response_note, responded_via')
          .eq('id', first.id)
          .single();
      expect(row, {
        'status': 'disputed',
        'response_note': 'ليس لي',
        'responded_via': 'app',
      });

      // Disputing it again: respond_entry refuses (55000) and B reloads.
      expect(await bView.disputeEntry(first.id, 'مرة ثانية'), isFalse);
      expect(bView.formError, 'تغيّرت حالة هذا القيد. أُعيد تحميل الدفتر.');
      expect(bView.entries.last.status, EntryStatus.disputed);

      // A withdraws the disputed 50.
      await aView.load();
      expect(await aView.withdrawEntry(first.id), isTrue);

      // B disputes 20, then confirms it after they settle it.
      expect(await bView.disputeEntry(second.id, 'لاحقاً'), isTrue);
      expect(await bView.confirmEntry(second.id), isTrue);

      // A cannot withdraw what is confirmed.
      await aView.load();
      expect(await aView.withdrawEntry(second.id), isFalse);
      expect(aView.formError, 'تغيّرت حالة هذا القيد. أُعيد تحميل الدفتر.');

      await bView.load();
      (int, EntryStatus) view(LedgerEntry e) => (e.myDeltaMinor, e.status);
      expect(aView.entries.map(view), [
        (2000, EntryStatus.confirmed),
        (5000, EntryStatus.voided),
      ]);
      expect(bView.entries.map(view), [
        (-2000, EntryStatus.confirmed),
        (-5000, EntryStatus.voided),
      ]);
      expect(aView.ledger!.myConfirmedMinor, 2000);
      expect(aView.ledger!.myOpenMinor, 2000);
      expect(bView.ledger!.myConfirmedMinor, -2000);
      expect(bView.ledger!.pendingCount + bView.ledger!.disputedCount, 0);
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'share link: created from the screen, read and answered without sign-in',
    () async {
      // Setup through RLS as A: a new shop ledger for B's phone, linked to B.
      final shopName = 'live link ${DateTime.now().toUtc()}';
      final shop = await a.client
          .from('businesses')
          .insert({'name': shopName})
          .select('id')
          .single();
      final ledger = await a.client
          .from('ledgers')
          .insert({
            'business_id': shop['id'],
            'counterparty_name': 'تجربة ب',
            'counterparty_phone': '966500000002',
          })
          .select('id')
          .single();
      final ledgerId = ledger['id'] as String;
      expect(await b.relaunch(), greaterThanOrEqualTo(1));

      final aView = LedgerController(
        SupabaseLedgerRepository(a.client),
        ledgerId,
      );
      final bView = LedgerController(
        SupabaseLedgerRepository(b.client),
        ledgerId,
      );
      addTearDown(aView.dispose);
      addTearDown(bView.dispose);
      await aView.load();
      await bView.load();
      expect(await aView.addEntry(iGave: true, amount: '12.5'), isTrue);
      expect(await bView.addEntry(iGave: true, amount: '2'), isTrue);

      // The other party cannot make a link; the owner can.
      expect(await bView.createShareLink(), isNull);
      final url = await aView.createShareLink();
      expect(url, startsWith(DainConfig.shareBaseUrl));
      final token = url!.substring(url.indexOf('#') + 1);
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));

      // What share/ calls, as anon: the contract the page relies on.
      final anon = SupabaseClient(
        DainConfig.supabaseUrl,
        DainConfig.supabaseKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(anon.dispose);
      Future<Map<String, dynamic>> read(String t) async =>
          await anon.rpc<dynamic>('get_shared_ledger', params: {'p_token': t})
              as Map<String, dynamic>;

      final page = await read(token);
      expect(page['owner_name'], shopName);
      expect(page['counterparty_name'], 'تجربة ب');
      expect(page['currency'], 'SAR');
      expect(page['confirmed_balance_minor'], 0);
      final entries = (page['entries'] as List).cast<Map<String, dynamic>>();
      expect(
        entries.map(
          (e) => (
            e['direction'],
            e['amount_minor'],
            e['status'],
            e['can_respond'],
          ),
        ),
        [('in', 200, 'pending', false), ('out', 1250, 'pending', true)],
      );
      expect(entries.first.keys.toSet(), {
        'id',
        'direction',
        'amount_minor',
        'note',
        'occurred_on',
        'status',
        'can_respond',
      });

      // Disputed through the link, with its reason; the owner sees it.
      final ownerEntry = entries.last['id'] as String;
      final status = await anon.rpc<dynamic>(
        'respond_by_token',
        params: {
          'p_token': token,
          'p_entry_id': ownerEntry,
          'p_decision': 'disputed',
          'p_note': 'ليس 12.5',
        },
      );
      expect(status, 'disputed');
      await aView.load();
      final seen = aView.entries.singleWhere((e) => e.id == ownerEntry);
      expect(seen.status, EntryStatus.disputed);
      expect(seen.responseNote, 'ليس 12.5');

      // A new link replaces the old one; stopping it kills the new one.
      final again = await aView.createShareLink();
      final token2 = again!.substring(again.indexOf('#') + 1);
      expect(token2, isNot(token));
      Future<String?> code(String t) async {
        try {
          await read(t);
          return null;
        } on PostgrestException catch (e) {
          return e.code;
        }
      }

      expect(await code(token), 'P0002');
      expect((await read(token2))['owner_name'], shopName);
      expect(await aView.revokeShareLink(), isTrue);
      expect(aView.shareUrl, isNull);
      expect(await code(token2), 'P0002');
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the database itself refuses a dispute without a reason',
    () async {
      // Setup through RLS as A: a new shop ledger for B's phone, linked to B.
      final shop = await a.client
          .from('businesses')
          .insert({'name': 'live reason ${DateTime.now().toUtc()}'})
          .select('id')
          .single();
      final ledger = await a.client
          .from('ledgers')
          .insert({
            'business_id': shop['id'],
            'counterparty_name': 'تجربة ب',
            'counterparty_phone': '966500000002',
          })
          .select('id')
          .single();
      final ledgerId = ledger['id'] as String;
      expect(await b.relaunch(), greaterThanOrEqualTo(1));
      final aView = LedgerController(
        SupabaseLedgerRepository(a.client),
        ledgerId,
      );
      addTearDown(aView.dispose);
      await aView.load();
      expect(await aView.addEntry(iGave: true, amount: '15'), isTrue);
      expect(await aView.addEntry(iGave: true, amount: '8'), isTrue);
      final [byLink, inApp] = aView.entries; // newest first

      const applyFirst =
          'apply supabase/migrations/20261021000000_dispute_reason.sql '
          'in the Supabase SQL Editor first';
      Future<String?> code(Future<dynamic> call) async {
        try {
          await call;
          return null;
        } on PostgrestException catch (e) {
          return e.code;
        }
      }

      // B calls respond_entry directly, skipping the app's own check.
      for (final note in [null, '   ']) {
        expect(
          await code(
            b.client.rpc<dynamic>(
              'respond_entry',
              params: {
                'p_entry_id': inApp.id,
                'p_decision': 'disputed',
                'p_note': note,
              },
            ),
          ),
          '22023',
          reason: '$applyFirst (note: $note)',
        );
      }
      await b.client.rpc<dynamic>(
        'respond_entry',
        params: {
          'p_entry_id': inApp.id,
          'p_decision': 'disputed',
          'p_note': '  ليس 15 ',
        },
      );
      final row = await a.client
          .from('entries')
          .select('status, response_note')
          .eq('id', inApp.id)
          .single();
      expect(row, {'status': 'disputed', 'response_note': 'ليس 15'});

      // The same through the share link, as anon.
      final url = await aView.createShareLink();
      final token = url!.substring(url.indexOf('#') + 1);
      final anon = SupabaseClient(
        DainConfig.supabaseUrl,
        DainConfig.supabaseKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(anon.dispose);
      expect(
        await code(
          anon.rpc<dynamic>(
            'respond_by_token',
            params: {
              'p_token': token,
              'p_entry_id': byLink.id,
              'p_decision': 'disputed',
            },
          ),
        ),
        '22023',
        reason: applyFirst,
      );
      expect(
        await anon.rpc<dynamic>(
          'respond_by_token',
          params: {
            'p_token': token,
            'p_entry_id': byLink.id,
            'p_decision': 'disputed',
            'p_note': 'ليس لي',
          },
        ),
        'disputed',
      );
      await aView.revokeShareLink();
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'my shops: rename, delete an empty one; one with a ledger stays',
    () async {
      final aRepo = SupabaseLedgerRepository(a.client);
      final stamp = DateTime.now().toUtc().toIso8601String();
      final empty = await aRepo.createBusiness('live empty $stamp');
      final busy = await aRepo.createBusiness('live busy $stamp');
      await a.client.from('ledgers').insert({
        'business_id': busy.id,
        'counterparty_name': 'تجربة ب',
        'counterparty_phone': '966500000002',
      });

      final shops = ShopsController(aRepo);
      addTearDown(shops.dispose);
      await shops.load();
      expect(shops.error, isNull);
      Business? named(String id) =>
          shops.shops!.where((s) => s.id == id).firstOrNull;

      expect(await shops.rename(empty.id, ' live renamed $stamp '), isTrue);
      expect(named(empty.id)?.name, 'live renamed $stamp');

      // The ledger keeps its shop: the foreign key refuses (23503).
      expect(await shops.delete(busy.id), isFalse);
      expect(shops.formError, startsWith('لا يُحذف محل فيه دفاتر.'));
      expect(named(busy.id), isNotNull);

      expect(await shops.delete(empty.id), isTrue);
      expect(named(empty.id), isNull);

      // B cannot rename A's shop, even once linked and able to see it.
      expect(await b.relaunch(), greaterThanOrEqualTo(1));
      final bShops = ShopsController(SupabaseLedgerRepository(b.client));
      addTearDown(bShops.dispose);
      expect(await bShops.rename(busy.id, 'hacked'), isFalse);
      await shops.load();
      expect(named(busy.id)?.name, 'live busy $stamp');
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'reminders: the owner sets one, sends it with a fresh link, only once due',
    () async {
      // Setup through RLS as A: a new shop ledger for B's phone, linked to B.
      final shop = await a.client
          .from('businesses')
          .insert({'name': 'live remind ${DateTime.now().toUtc()}'})
          .select('id')
          .single();
      final ledger = await a.client
          .from('ledgers')
          .insert({
            'business_id': shop['id'],
            'counterparty_name': 'تجربة ب',
            'counterparty_phone': '966500000002',
          })
          .select('id')
          .single();
      final ledgerId = ledger['id'] as String;
      expect(await b.relaunch(), greaterThanOrEqualTo(1));
      final aView = LedgerController(
        SupabaseLedgerRepository(a.client),
        ledgerId,
      );
      final bView = LedgerController(
        SupabaseLedgerRepository(b.client),
        ledgerId,
      );
      addTearDown(aView.dispose);
      addTearDown(bView.dispose);
      await aView.load();
      expect(await aView.addEntry(iGave: true, amount: '10'), isTrue);
      await bView.load();
      expect(await bView.confirmEntry(bView.entries.single.id), isTrue);

      // Off by default; set every 7 days: never sent and owed, so due.
      await aView.load();
      expect(aView.reminderIsDue, isFalse);
      expect(await aView.setReminder(7), isTrue, reason: aView.formError);
      expect(aView.ledger!.remindEveryDays, 7);
      expect(aView.reminderIsDue, isTrue);

      final copied = <String>[];
      final message = await aView.sendReminder((t) async => copied.add(t));
      expect(
        message,
        isNotNull,
        reason:
            '${aView.formError}: apply supabase/migrations/'
            '20261022000000_mark_reminded.sql in the SQL Editor first',
      );
      expect(copied, [message]);
      expect(message, contains('10 ر.س عليك'));
      final token = message!.substring(message.indexOf('#') + 1);
      final anon = SupabaseClient(
        DainConfig.supabaseUrl,
        DainConfig.supabaseKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(anon.dispose);
      final page = await anon.rpc<dynamic>(
        'get_shared_ledger',
        params: {'p_token': token},
      );
      expect((page as Map)['confirmed_balance_minor'], 1000);

      // Stamped by the server just now: no longer due.
      final last = aView.ledger!.lastRemindedAt!;
      expect(DateTime.now().difference(last).inMinutes.abs(), lessThan(5));
      expect(aView.reminderIsDue, isFalse);

      // B sees no reminder, and the database refuses B's attempts.
      await bView.load();
      expect(bView.ledger!.remindEveryDays, isNull);
      expect(await bView.setReminder(1), isFalse);
      final changed = await b.client
          .from('ledgers')
          .update({'remind_every_days': 1})
          .eq('id', ledgerId)
          .select('id');
      expect(changed, isEmpty);
      String? code;
      try {
        await b.client.rpc<dynamic>(
          'mark_reminded',
          params: {'p_ledger_id': ledgerId},
        );
      } on PostgrestException catch (e) {
        code = e.code;
      }
      expect(
        code,
        'P0002',
        reason:
            'apply supabase/migrations/20261022000000_mark_reminded.sql '
            'in the Supabase SQL Editor first',
      );

      expect(await aView.setReminder(null), isTrue);
      expect(aView.ledger!.remindEveryDays, isNull);
      await aView.revokeShareLink();
    },
    skip: _live ? false : 'live test: pass --dart-define=DAIN_LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
