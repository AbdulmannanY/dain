import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

LedgerSummary ledger({
  bool owner = true,
  int confirmed = 0,
  int open = 0,
  int pending = 0,
  bool joined = true,
}) => LedgerSummary(
  id: 'L1',
  iAmOwner: owner,
  title: owner ? 'سعد' : 'بقالة النور',
  subtitle: owner ? null : 'خالد',
  currency: 'SAR',
  myConfirmedMinor: confirmed,
  myOpenMinor: open,
  pendingCount: pending,
  disputedCount: 0,
  otherPartyJoined: joined,
);

LedgerEntry entry(
  String id,
  int delta, {
  EntryStatus status = EntryStatus.pending,
  bool mine = true,
  String? note,
}) => LedgerEntry(
  id: id,
  myDeltaMinor: delta,
  note: note,
  occurredOn: DateTime(2026, 10, 20),
  status: status,
  createdByMe: mine,
  responseNote: null,
);

/// The ledger's screen, reached by tapping it in the list of the real
/// DainApp, on a phone-sized screen (overflow fails the test).
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late FakeLedgers ledgers;

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers();
  });

  Future<void> openLedger(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ledger_L1')));
    await tester.pumpAndSettle();
  }

  Future<void> record(
    WidgetTester tester, {
    required bool gave,
    required String amount,
    String note = '',
  }) async {
    final button = gave ? 'add_gave_button' : 'add_took_button';
    await tester.tap(find.byKey(Key(button)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount_field')), amount);
    await tester.enterText(find.byKey(const Key('note_field')), note);
    await tester.tap(find.byKey(const Key('save_entry_button')));
    await tester.pumpAndSettle();
  }

  Finder inEntry(String id, String text) => find.descendant(
    of: find.byKey(Key('entry_$id')),
    matching: find.textContaining(text),
  );

  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  testWidgets('shows the balance and the entries from my side', (tester) async {
    ledgers.ledgers = [ledger(confirmed: 4550, open: 3550, pending: 1)];
    ledgers.entries['L1'] = [
      entry('a', -1000, mine: false),
      entry('b', 4550, status: EntryStatus.confirmed, note: 'أرز'),
      entry('c', 999, status: EntryStatus.voided),
    ];
    await openLedger(tester);

    expect(find.widgetWithText(AppBar, 'سعد'), findsOneWidget);
    final balance = find.byKey(const Key('ledger_balance'));
    for (final t in ['لك', '45.50 ر.س', 'مع المعلّق: لك 35.50 ر.س']) {
      expect(
        find.descendant(of: balance, matching: find.text(t)),
        findsOneWidget,
        reason: t,
      );
    }
    expect(inEntry('a', 'أخذت 10 ر.س'), findsOneWidget);
    expect(inEntry('a', 'سجّله الطرف الآخر · بانتظار تأكيدك'), findsOneWidget);
    expect(inEntry('b', 'أعطيت 45.50 ر.س'), findsOneWidget);
    expect(
      inEntry('b', 'أرز · 20/10/2026 · سجّلته أنت · مؤكد'),
      findsOneWidget,
    );
    expect(inEntry('c', 'مسحوب'), findsOneWidget);
  });

  testWidgets(
    'the counterparty records "I gave": stored as in, shown as gave',
    (tester) async {
      ledgers.ledgers = [ledger(owner: false)];
      await openLedger(tester);
      expect(find.byKey(const Key('entries_empty')), findsOneWidget);
      final fetchesBefore = ledgers.fetches;

      await record(tester, gave: true, amount: '٥٠٫٥', note: ' ثمن الغداء ');

      expect(ledgers.added, [('L1', 'in', 5050, 'ثمن الغداء', today())]);
      expect(find.byKey(const Key('save_entry_button')), findsNothing);
      expect(
        find.text('سُجّل القيد. ينتظر تأكيد الطرف الآخر.'),
        findsOneWidget,
      );
      expect(inEntry('e1', 'أعطيت 50.50 ر.س'), findsOneWidget);
      expect(inEntry('e1', 'بانتظار التأكيد'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('ledger_balance')),
          matching: find.text('مع المعلّق: لك 50.50 ر.س'),
        ),
        findsOneWidget,
      );

      // Back on the list, balances are read again.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(ledgers.fetches, greaterThan(fetchesBefore));
    },
  );

  testWidgets('the owner records "I took": stored as in, without a note', (
    tester,
  ) async {
    ledgers.ledgers = [ledger(joined: false)];
    await openLedger(tester);
    expect(find.byKey(const Key('not_joined_note')), findsOneWidget);

    await record(tester, gave: false, amount: '1,250');

    expect(ledgers.added, [('L1', 'in', 125000, null, today())]);
    expect(inEntry('e1', 'أخذت 1,250 ر.س'), findsOneWidget);
  });

  testWidgets('a bad amount or a long note stays in the sheet', (tester) async {
    ledgers.ledgers = [ledger()];
    await openLedger(tester);

    for (final bad in ['', '0', '1.234', 'abc']) {
      if (find.byKey(const Key('amount_field')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('add_gave_button')));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const Key('amount_field')), bad);
      await tester.tap(find.byKey(const Key('save_entry_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('أدخل مبلغاً صحيحاً، مثل 45.50.'),
        findsOneWidget,
        reason: bad,
      );
    }
    await tester.enterText(find.byKey(const Key('amount_field')), '5');
    await tester.enterText(find.byKey(const Key('note_field')), 'ن' * 201);
    await tester.tap(find.byKey(const Key('save_entry_button')));
    await tester.pumpAndSettle();
    expect(find.text('الملاحظة حتى 200 حرف.'), findsOneWidget);
    expect(ledgers.added, isEmpty);
  });

  testWidgets('a failed save keeps the sheet; saving again records once', (
    tester,
  ) async {
    ledgers.ledgers = [ledger()];
    ledgers.failNextAddWith = const PostgrestException(
      message: 'boom',
      code: '500',
    );
    await openLedger(tester);

    await record(tester, gave: true, amount: '20');
    expect(
      find.descendant(
        of: find.byKey(const Key('entry_error_text')),
        matching: find.text('تعذّر إتمام العملية. حاول مجدداً.'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(ledgers.added, isEmpty);

    await tester.tap(find.byKey(const Key('save_entry_button')));
    await tester.pumpAndSettle();
    expect(ledgers.added, hasLength(1));
    expect(find.byKey(const Key('save_entry_button')), findsNothing);

    // A new sheet starts without the old error.
    await tester.tap(find.byKey(const Key('add_took_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry_error_text')), findsNothing);
  });

  testWidgets('a failed first load offers a retry', (tester) async {
    ledgers.ledgers = [ledger()];
    await openLedger(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    ledgers.failWith = const PostgrestException(message: 'x', code: '500');
    // The list keeps its rows after a failed refresh, so the tile is there.
    await tester.tap(find.byKey(const Key('ledger_L1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('retry_button')), findsOneWidget);
    expect(find.byKey(const Key('add_gave_button')), findsNothing);

    ledgers.failWith = null;
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entries_empty')), findsOneWidget);
  });
}
