import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/ledgers/ledger_controller.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

LedgerSummary ledger({bool owner = true, bool joined = false}) => LedgerSummary(
  id: 'L1',
  iAmOwner: owner,
  title: 'سعد',
  subtitle: null,
  currency: 'SAR',
  myConfirmedMinor: 0,
  myOpenMinor: 0,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: joined,
  counterpartyPhone: owner ? '966501234567' : null,
);

/// The owner corrects the other party from the ledger's screen, through the
/// real DainApp on a phone-sized screen.
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late FakeLedgers ledgers;

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers()..myPhone = '966500000001';
  });

  Future<void> openSheet(WidgetTester tester, LedgerSummary l) async {
    ledgers.ledgers = [l];
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ledger_L1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_counterparty_button')));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, {String? name, String? phone}) async {
    if (name != null) {
      await tester.enterText(find.byKey(const Key('edit_name_field')), name);
    }
    if (phone != null) {
      await tester.enterText(find.byKey(const Key('edit_phone_field')), phone);
    }
    await tester.tap(find.byKey(const Key('save_counterparty_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('before joining: name and phone change; the link goes', (
    tester,
  ) async {
    ledgers.shareLinks['L1'] = 'tok';
    await openSheet(tester, ledger());
    expect(find.text('+966501234567'), findsOneWidget);

    await save(tester, name: ' نادر ', phone: '770827842');

    expect(ledgers.counterpartyEdits, [('L1', 'نادر', '967770827842')]);
    expect(ledgers.shareLinks, isEmpty);
    expect(find.widgetWithText(AppBar, 'نادر'), findsOneWidget);
    expect(find.text('حُفظت بيانات الطرف الآخر.'), findsOneWidget);
  });

  testWidgets('the same phone in another form is not sent again', (
    tester,
  ) async {
    await openSheet(tester, ledger());
    await save(tester, name: 'سعد علي', phone: '0501234567');
    expect(ledgers.counterpartyEdits, [('L1', 'سعد علي', null)]);
  });

  testWidgets('after joining only the name changes', (tester) async {
    await openSheet(tester, ledger(joined: true));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('edit_phone_field')))
          .enabled,
      isFalse,
    );
    expect(find.text('انضم بهذا الرقم، فلا يتغيّر.'), findsOneWidget);
    await save(tester, name: 'سعد');
    expect(ledgers.counterpartyEdits, [('L1', 'سعد', null)]);
  });

  testWidgets('my own number, a bad one, or a taken one is refused', (
    tester,
  ) async {
    await openSheet(tester, ledger());
    await save(tester, phone: '+966 50 000 0001');
    expect(find.text('هذا رقمك أنت. أدخل رقم الطرف الآخر.'), findsOneWidget);
    await save(tester, phone: '12');
    expect(find.textContaining('أدخل رقم جوال صحيحاً'), findsOneWidget);

    ledgers.failNextActionWith = const PostgrestException(
      message: 'duplicate',
      code: '23505',
    );
    await save(tester, phone: '770827842');
    expect(find.text('لديك دفتر آخر لهذا الرقم بالفعل.'), findsOneWidget);
    expect(ledgers.counterpartyEdits, isEmpty);
  });

  test('once joined, a phone handed to the controller is ignored', () async {
    ledgers.ledgers = [ledger(joined: true)];
    final c = LedgerController(ledgers, 'L1');
    addTearDown(c.dispose);
    await c.load();
    expect(await c.updateCounterparty(name: 'سعد', phone: '770827842'), isTrue);
    expect(ledgers.counterpartyEdits, [('L1', 'سعد', null)]);
  });

  testWidgets('the other party has no edit button', (tester) async {
    ledgers.ledgers = [ledger(owner: false, joined: true)];
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ledger_L1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit_counterparty_button')), findsNothing);
  });
}
