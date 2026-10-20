import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

LedgerSummary summary(
  String id,
  String title,
  int confirmed, {
  bool owner = true,
  String? subtitle,
  int pending = 0,
  int disputed = 0,
  bool joined = true,
}) => LedgerSummary(
  id: id,
  iAmOwner: owner,
  title: title,
  subtitle: subtitle,
  currency: 'SAR',
  myConfirmedMinor: confirmed,
  myOpenMinor: confirmed,
  pendingCount: pending,
  disputedCount: disputed,
  otherPartyJoined: joined,
);

/// Signed-in user with a profile, launched through the real DainApp.
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late FakeLedgers ledgers;

  Future<SessionController> launch(WidgetTester tester) async {
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    return c;
  }

  Finder inTile(String id, String text) => find.descendant(
    of: find.byKey(Key('ledger_$id')),
    matching: find.text(text),
  );

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers();
  });

  testWidgets('lists ledgers with balances from my side and totals', (
    tester,
  ) async {
    // Phone-sized screen: overflow would fail the test.
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ledgers.ledgers = [
      summary('1', 'سعد', 4550, pending: 2),
      summary(
        '2',
        'بقالة النور',
        -120000,
        owner: false,
        subtitle: 'خالد',
        disputed: 1,
      ),
      summary('3', 'فهد', 0, joined: false),
      summary(
        '4',
        'مؤسسة عبدالرحمن بن محمد للتجارة والمقاولات العامة',
        123456789,
        subtitle: 'فرع الرياض',
        pending: 12,
        disputed: 3,
      ),
    ];
    await launch(tester);

    expect(ledgers.fetches, 1);
    expect(find.text('أهلاً، أحمد'), findsOneWidget);

    expect(inTile('1', 'لك'), findsOneWidget);
    expect(inTile('1', '45.50 ر.س'), findsOneWidget);
    expect(inTile('1', '2 بانتظار التأكيد'), findsOneWidget);

    expect(inTile('2', 'عليك'), findsOneWidget);
    expect(inTile('2', '1,200 ر.س'), findsOneWidget);
    expect(inTile('2', 'خالد · 1 معترض عليه'), findsOneWidget);

    expect(inTile('3', 'لا رصيد'), findsOneWidget);
    expect(inTile('3', 'لم ينضم بعد'), findsOneWidget);
    expect(inTile('4', '1,234,567.89 ر.س'), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(const Key('total_owed_to_me_SAR')),
        matching: find.text('1,234,613.39 ر.س'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('total_i_owe_SAR')),
        matching: find.text('1,200 ر.س'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty state when I have no ledgers', (tester) async {
    await launch(tester);
    expect(find.byKey(const Key('ledgers_empty')), findsOneWidget);
    expect(find.byKey(const Key('total_owed_to_me_SAR')), findsNothing);
  });

  testWidgets('first load fails -> retry loads the list', (tester) async {
    ledgers.failWith = const PostgrestException(message: 'x', code: '500');
    await launch(tester);
    expect(find.byKey(const Key('retry_button')), findsOneWidget);
    expect(find.text('تعذّر إتمام العملية. حاول مجدداً.'), findsOneWidget);

    ledgers
      ..failWith = null
      ..ledgers = [summary('1', 'سعد', 100)];
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger_1')), findsOneWidget);
    expect(ledgers.fetches, 2);
  });

  testWidgets(
    'pull to refresh fetches again; a failed refresh keeps the list',
    (tester) async {
      ledgers.ledgers = [summary('1', 'سعد', 100)];
      await launch(tester);

      ledgers.ledgers = [summary('1', 'سعد', 100), summary('2', 'بدر', -50)];
      await tester.fling(
        find.byKey(const Key('ledgers_list')),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(ledgers.fetches, 2);
      expect(find.byKey(const Key('ledger_2')), findsOneWidget);

      ledgers.failWith = const PostgrestException(message: 'x', code: '500');
      await tester.fling(
        find.byKey(const Key('ledgers_list')),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(ledgers.fetches, 3);
      expect(find.byKey(const Key('ledger_2')), findsOneWidget);
      expect(find.byKey(const Key('error_text')), findsOneWidget);
    },
  );

  testWidgets('linked ledgers banner after sign-in links some', (tester) async {
    profiles.pendingLedgers = 3;
    await launch(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('linked_banner')),
        matching: find.text('أُضيف إلى حسابك 3 دفاتر مسجّلة برقمك.'),
      ),
      findsOneWidget,
    );
  });
}
