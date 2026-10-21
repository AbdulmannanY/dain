import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

LedgerEntry entry(
  String id,
  int delta, {
  EntryStatus status = EntryStatus.pending,
  bool mine = false,
}) => LedgerEntry(
  id: id,
  myDeltaMinor: delta,
  note: null,
  occurredOn: DateTime(2026, 10, 20),
  status: status,
  createdByMe: mine,
  responseNote: null,
);

/// Confirming, disputing and withdrawing entries from the ledger's screen,
/// through the real DainApp on a phone-sized screen.
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late FakeLedgers ledgers;

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers()
      ..ledgers = [
        const LedgerSummary(
          id: 'L1',
          iAmOwner: true,
          title: 'سعد',
          subtitle: null,
          currency: 'SAR',
          myConfirmedMinor: 0,
          myOpenMinor: -2000,
          pendingCount: 1,
          disputedCount: 0,
          otherPartyJoined: true,
        ),
      ];
  });

  Future<void> openEntry(WidgetTester tester, LedgerEntry e) async {
    ledgers.entries['L1'] = [e];
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ledger_L1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('entry_${e.id}')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Finder inEntry(String id, String text) => find.descendant(
    of: find.byKey(Key('entry_$id')),
    matching: find.textContaining(text),
  );

  Finder balance(String text) => find.descendant(
    of: find.byKey(const Key('ledger_balance')),
    matching: find.text(text),
  );

  testWidgets('confirming their entry moves it into the agreed balance', (
    tester,
  ) async {
    await openEntry(tester, entry('a', -2000));
    expect(find.byKey(const Key('withdraw_entry_button')), findsNothing);

    await tap(tester, 'confirm_entry_button');

    expect(ledgers.actions, [('a', 'confirmed', null)]);
    expect(find.byKey(const Key('confirm_entry_button')), findsNothing);
    expect(find.text('أُكّد القيد.'), findsOneWidget);
    expect(inEntry('a', 'مؤكد'), findsOneWidget);
    expect(balance('عليك'), findsOneWidget);
    expect(balance('20 ر.س'), findsOneWidget);
  });

  testWidgets('a dispute needs a reason, which is shown on the entry', (
    tester,
  ) async {
    await openEntry(tester, entry('a', -2000));
    await tap(tester, 'dispute_entry_button');
    expect(find.byKey(const Key('confirm_entry_button')), findsNothing);

    await tap(tester, 'send_dispute_button');
    expect(find.text('اكتب سبب الاعتراض (حتى 200 حرف).'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('dispute_reason_field')),
      'ن' * 201,
    );
    await tap(tester, 'send_dispute_button');
    expect(find.text('اكتب سبب الاعتراض (حتى 200 حرف).'), findsOneWidget);
    expect(ledgers.actions, isEmpty);

    await tester.enterText(
      find.byKey(const Key('dispute_reason_field')),
      '  المبلغ 15 لا 20 ',
    );
    await tap(tester, 'send_dispute_button');

    expect(ledgers.actions, [('a', 'disputed', 'المبلغ 15 لا 20')]);
    expect(find.text('أُرسل الاعتراض.'), findsOneWidget);
    expect(inEntry('a', 'معترض عليه · الرد: المبلغ 15 لا 20'), findsOneWidget);
    expect(balance('1 معترض عليه'), findsOneWidget);

    // A disputed entry of theirs can still be confirmed, not disputed again.
    await tap(tester, 'entry_a');
    expect(find.byKey(const Key('confirm_entry_button')), findsOneWidget);
    expect(find.byKey(const Key('dispute_entry_button')), findsNothing);
  });

  testWidgets('withdrawing my own entry takes a second tap', (tester) async {
    await openEntry(tester, entry('m', 3000, mine: true));
    expect(find.byKey(const Key('confirm_entry_button')), findsNothing);
    expect(find.byKey(const Key('dispute_entry_button')), findsNothing);

    await tap(tester, 'withdraw_entry_button');
    expect(ledgers.actions, isEmpty);
    await tap(tester, 'confirm_withdraw_button');

    expect(ledgers.actions, [('m', 'voided', null)]);
    expect(find.text('سُحب القيد.'), findsOneWidget);
    expect(inEntry('m', 'مسحوب'), findsOneWidget);
  });

  testWidgets('a confirmed entry offers nothing but how to correct it', (
    tester,
  ) async {
    await openEntry(
      tester,
      entry('k', 500, mine: true, status: EntryStatus.confirmed),
    );
    expect(
      find.text('قيد مؤكد لا يُعدَّل. للتصحيح سجّل قيداً معاكساً.'),
      findsOneWidget,
    );
    for (final k in [
      'confirm_entry_button',
      'dispute_entry_button',
      'withdraw_entry_button',
    ]) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
  });

  testWidgets(
    'if they acted first, the sheet says so and shows the new state',
    (tester) async {
      await openEntry(tester, entry('m', 3000, mine: true));
      await tap(tester, 'withdraw_entry_button');

      // Meanwhile the other party confirmed it: void_entry refuses (55000).
      ledgers.entries['L1'] = [
        entry('m', 3000, mine: true, status: EntryStatus.confirmed),
      ];
      ledgers.failNextActionWith = const PostgrestException(
        message: 'entry is confirmed, cannot be voided',
        code: '55000',
      );
      await tap(tester, 'confirm_withdraw_button');

      expect(
        find.text('تغيّرت حالة هذا القيد. أُعيد تحميل الدفتر.'),
        findsOneWidget,
      );
      expect(ledgers.actions, isEmpty);
      // Reloaded: the sheet now shows the confirmed entry, without the step.
      expect(find.byKey(const Key('confirm_withdraw_button')), findsNothing);
      expect(find.byKey(const Key('entry_final_note')), findsOneWidget);
    },
  );
}
