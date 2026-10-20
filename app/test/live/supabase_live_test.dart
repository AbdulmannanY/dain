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

  Future<void> close() async {
    await client.auth.signOut();
    await client.dispose();
  }
}

void main() {
  HttpOverrides.global = _EnvProxyOverrides();

  test(
    'A records a ledger for B\'s phone; B signs in and it is linked to B',
    () async {
      final a = _Session();
      final b = _Session();
      addTearDown(a.close);
      addTearDown(b.close);

      await a.signIn('0500000001', 'تجربة أ');

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

      await b.signIn('+966 50 000 0002', 'تجربة ب');
      expect(b.controller.linkedCount, greaterThanOrEqualTo(1));

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
      final a = _Session();
      final b = _Session();
      addTearDown(a.close);
      addTearDown(b.close);

      await a.signIn('0500000001', 'تجربة أ');
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

      await b.signIn('0500000002', 'تجربة ب');
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
}
