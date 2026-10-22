import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/ledgers/ledger_controller.dart';
import 'package:dain/ledgers/ledgers_controller.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

LedgerSummary ledger({
  String id = 'L1',
  bool owner = true,
  int confirmed = 4550,
  DateTime? due,
}) => LedgerSummary(
  id: id,
  iAmOwner: owner,
  title: 'سعد',
  subtitle: null,
  currency: 'SAR',
  myConfirmedMinor: confirmed,
  myOpenMinor: confirmed,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: true,
  dueOn: due,
);

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

void main() {
  final day = DateTime(2026, 10, 22);

  test('overdue only after the day, and only while a balance is open', () {
    final before = DateTime(2026, 10, 21);
    expect(paymentOverdue(ledger(due: before), day), isTrue);
    expect(paymentOverdue(ledger(due: before, confirmed: -100), day), isTrue);
    expect(paymentOverdue(ledger(due: day), day), isFalse);
    expect(paymentOverdue(ledger(due: before, confirmed: 0), day), isFalse);
    expect(paymentOverdue(ledger(), day), isFalse);
  });

  test('buildSummaries reads due_on for both sides', () {
    Map<String, dynamic> row(String owner) => {
      'id': 'L1',
      'owner_id': owner,
      'counterparty_id': 'cp',
      'counterparty_name': 'سعد',
      'currency': 'SAR',
      'due_on': '2026-11-05',
      'business': null,
      'owner': {'full_name': 'أحمد'},
    };
    for (final (owner, me) in [('me', 'me'), ('owner', 'cp')]) {
      final l = buildSummaries(
        ledgerRows: [row(owner)],
        balanceRows: const [],
        myId: me,
      ).single;
      expect(l.dueOn, DateTime(2026, 11, 5), reason: me);
    }
  });

  test('the reminder message names the repayment day', () {
    expect(
      reminderMessage(ledger(due: DateTime(2026, 11, 5)), 'u'),
      'السلام عليكم سعد،\n'
      'تذكير بالرصيد المتفق عليه: 45.50 ر.س عليك.\n'
      'موعد السداد: 5/11/2026.\n'
      'التفاصيل، وتأكيد القيود أو الاعتراض عليها:\n'
      'u',
    );
  });

  test('sorting by the repayment day: nearest first, none last', () {
    final list = [
      ledger(id: 'none'),
      ledger(id: 'late', due: DateTime(2026, 12, 1)),
      ledger(id: 'soon', due: DateTime(2026, 10, 1)),
    ];
    expect(
      [for (final l in searchLedgers(list, sort: LedgerSort.due)) l.id],
      ['soon', 'late', 'none'],
    );
  });

  test('only the owner sets one', () async {
    final repo = FakeLedgers([ledger(owner: false)]);
    final c = LedgerController(repo, 'L1');
    await c.load();
    expect(await c.setDueDate(day), isFalse);
    expect(repo.dueDates, isEmpty);
  });

  group('on the screens', () {
    late FakeLedgers ledgers;

    Future<void> launch(WidgetTester tester, LedgerSummary l) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = FakeAuth(signedInAs: '966500000001');
      final profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
      ledgers = FakeLedgers([l]);
      final c = SessionController(auth: auth, profiles: profiles);
      await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
      await c.start();
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('the owner picks a day, sees it, then clears it', (
      tester,
    ) async {
      await launch(tester, ledger(confirmed: 0));
      await tap(tester, 'ledger_L1');
      expect(find.byKey(const Key('due_text')), findsNothing);

      await tap(tester, 'reminder_button');
      await tap(tester, 'due_date_button');
      final t = today();
      final picked = DateTime(t.year, t.month, 28);
      await tester.tap(find.text('28'));
      await tester.tap(find.text('حسنًا'));
      await tester.pumpAndSettle();
      expect(ledgers.dueDates, [('L1', picked)]);
      expect(
        find.descendant(
          of: find.byKey(const Key('due_date_button')),
          matching: find.text(shortDay(picked)),
        ),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(180, 40)); // close the sheet
      await tester.pumpAndSettle();
      // Nothing is owed, so it is never shown as overdue.
      expect(
        find.descendant(
          of: find.byKey(const Key('due_text')),
          matching: find.text('موعد السداد: ${shortDay(picked)}'),
          matchRoot: true,
        ),
        findsOneWidget,
      );

      await tap(tester, 'reminder_button');
      await tap(tester, 'clear_due_button');
      expect(ledgers.dueDates.last, ('L1', null));
      expect(find.byKey(const Key('clear_due_button')), findsNothing);
    });

    testWidgets(
      'a passed day with a balance shows as overdue on both screens',
      (tester) async {
        final t = today();
        final due = DateTime(t.year, t.month, t.day - 3);
        await launch(tester, ledger(owner: false, confirmed: -4550, due: due));
        expect(
          find.descendant(
            of: find.byKey(const Key('ledger_L1')),
            matching: find.textContaining('فات موعد السداد'),
          ),
          findsOneWidget,
        );

        await tap(tester, 'ledger_L1');
        expect(
          find.descendant(
            of: find.byKey(const Key('due_text')),
            matching: find.text('موعد السداد: ${shortDay(due)} · فات الموعد'),
            matchRoot: true,
          ),
          findsOneWidget,
        );
        // The counterparty sees it but cannot change it.
        expect(find.byKey(const Key('reminder_button')), findsNothing);
      },
    );

    testWidgets('a day still ahead is shown on the list tile', (tester) async {
      final t = today();
      final due = DateTime(t.year, t.month, t.day + 5);
      await launch(tester, ledger(due: due));
      expect(
        find.descendant(
          of: find.byKey(const Key('ledger_L1')),
          matching: find.textContaining('السداد ${shortDay(due)}'),
        ),
        findsOneWidget,
      );
    });
  });
}
