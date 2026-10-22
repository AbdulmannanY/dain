import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/ledgers/statement.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

LedgerSummary ledger({bool owner = true, String? shop}) => LedgerSummary(
  id: 'L1',
  iAmOwner: owner,
  title: 'سعد',
  subtitle: shop,
  currency: 'SAR',
  myConfirmedMinor: 7000,
  myOpenMinor: 7700,
  pendingCount: 1,
  disputedCount: 0,
  otherPartyJoined: true,
);

var _ids = 0;

LedgerEntry entry(
  int delta,
  DateTime day, {
  EntryStatus status = EntryStatus.confirmed,
  bool payment = false,
  String? note,
}) => LedgerEntry(
  id: 'e${++_ids}abcdef-0000-4000-8000-000000000000',
  myDeltaMinor: delta,
  note: note,
  occurredOn: day,
  status: status,
  createdByMe: true,
  responseNote: null,
  isPayment: payment,
);

/// Newest first, as fetchEntries returns them.
List<LedgerEntry> newestFirst(List<LedgerEntry> oldestFirst) =>
    oldestFirst.reversed.toList();

void main() {
  group('the period', () {
    final today = DateTime(2026, 10, 22, 15, 30);
    test('this month, last month, this year and everything', () {
      expect(statementRange(StatementPeriod.thisMonth, today), (
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 22),
      ));
      expect(statementRange(StatementPeriod.lastMonth, today), (
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      ));
      expect(statementRange(StatementPeriod.thisYear, today), (
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 10, 22),
      ));
      expect(statementRange(StatementPeriod.all, today), (
        from: null,
        to: DateTime(2026, 10, 22),
      ));
    });

    test('last month across a new year, and in February', () {
      expect(statementRange(StatementPeriod.lastMonth, DateTime(2027, 1, 5)), (
        from: DateTime(2026, 12, 1),
        to: DateTime(2026, 12, 31),
      ));
      expect(statementRange(StatementPeriod.lastMonth, DateTime(2028, 3, 31)), (
        from: DateTime(2028, 2, 1),
        to: DateTime(2028, 2, 29),
      ));
    });
  });

  group('the statement', () {
    final entries = newestFirst([
      entry(10000, DateTime(2026, 9, 12)), // before: opening
      entry(-2500, DateTime(2026, 9, 30), status: EntryStatus.disputed),
      entry(-1000, DateTime(2026, 9, 30), payment: true),
      entry(-3000, DateTime(2026, 10, 2), payment: true, note: 'نقداً'),
      entry(500, DateTime(2026, 10, 2)),
      entry(900, DateTime(2026, 10, 5), status: EntryStatus.voided),
      entry(700, DateTime(2026, 10, 10), status: EntryStatus.pending),
      entry(-200, DateTime(2026, 10, 12), status: EntryStatus.disputed),
      entry(4000, DateTime(2026, 10, 20)),
      entry(50, DateTime(2026, 10, 23)), // after the period
    ]);

    test('opening, each agreed movement with its balance, closing', () {
      final s = buildStatement(
        ledger(),
        entries,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 22),
      );
      expect(s.openingMinor, 9000);
      expect(
        [for (final l in s.lines) (l.entry.myDeltaMinor, l.balanceMinor)],
        [(-3000, 6000), (500, 6500), (4000, 10500)],
      );
      expect(s.closingMinor, 10500);
      // pending and disputed in the period are counted, not added
      expect(s.unconfirmedCount, 2);
      expect((s.increasedMinor, s.decreasedMinor), (4500, 3000));
    });

    test('from the start: no opening, every agreed movement', () {
      final s = buildStatement(
        ledger(),
        entries,
        from: null,
        to: DateTime(2026, 10, 22),
      );
      expect(s.openingMinor, 0);
      expect(s.lines, hasLength(5));
      expect(s.closingMinor, 10500);
      expect(s.unconfirmedCount, 3);
    });

    test('a period with no movement keeps the balance', () {
      final s = buildStatement(
        ledger(),
        entries,
        from: DateTime(2026, 10, 21),
        to: DateTime(2026, 10, 22),
      );
      expect((s.openingMinor, s.closingMinor), (10500, 10500));
      expect(s.lines, isEmpty);
    });

    test('entries of one day stay in the order they were recorded', () {
      final day = DateTime(2026, 10, 2);
      final first = entry(100, day);
      final second = entry(-50, day);
      final s = buildStatement(ledger(), [second, first], from: day, to: day);
      expect([for (final l in s.lines) l.entry.id], [first.id, second.id]);
      expect([for (final l in s.lines) l.balanceMinor], [100, 50]);
    });

    test('as text, to send', () {
      final s = buildStatement(
        ledger(shop: 'بقالة النور'),
        newestFirst([
          entry(10000, DateTime(2026, 9, 12)),
          entry(-3000, DateTime(2026, 10, 2), payment: true, note: 'نقداً'),
          entry(700, DateTime(2026, 10, 10), status: EntryStatus.pending),
        ]),
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 22),
      );
      expect(
        statementText(s),
        'كشف حساب سعد (بقالة النور)\n'
        'الفترة: من 1/10/2026 إلى 22/10/2026\n'
        'الرصيد السابق: 100 ر.س لك\n'
        '2/10/2026 · استلمت سداداً 30 ر.س · نقداً · الرصيد 70 ر.س لك\n'
        'الرصيد النهائي: 70 ر.س لك\n'
        'لا يشمل قيوداً لم تُؤكَّد بعد: 1.\n'
        'من دائن: القيود التي أكّدها الطرفان فقط.',
      );
    });

    test('as CSV: signed amounts, quoted text, no formulas', () {
      final pay = entry(3050, DateTime(2026, 10, 2), payment: true);
      final odd = entry(
        500,
        DateTime(2026, 10, 3),
        note: '=HYPERLINK("x"), "y"',
      );
      final s = buildStatement(
        ledger(),
        newestFirst([entry(-10000, DateTime(2026, 9, 1)), pay, odd]),
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 22),
      );
      expect(
        statementCsv(s),
        'التاريخ,البيان,المبلغ (SAR),الرصيد (SAR),الملاحظة,الرقم\r\n'
        '2026-10-01,الرصيد السابق,,-100,,\r\n'
        '2026-10-02,سدّدت,30.50,-69.50,,${entryRef(pay.id)}\r\n'
        '2026-10-03,أعطيت,5,-64.50,'
        '"\'=HYPERLINK(""x""), ""y""",${entryRef(odd.id)}\r\n'
        '2026-10-22,الرصيد النهائي,,-64.50,,\r\n',
      );
    });
  });

  group('the statement screen', () {
    late List<String> clipboard;

    testWidgets('from the ledger: periods, balances, and both copies', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      clipboard = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final longAgo = DateTime(now.year - 1, now.month, 1);
      final auth = FakeAuth(signedInAs: '966500000001');
      final profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
      final ledgers = FakeLedgers([ledger()]);
      final paid = entry(-3000, today, payment: true);
      ledgers.entries['L1'] = newestFirst([
        entry(10000, longAgo),
        paid,
        entry(700, today, status: EntryStatus.pending),
      ]);
      final session = SessionController(auth: auth, profiles: profiles);
      await tester.pumpWidget(DainApp(controller: session, ledgers: ledgers));
      await session.start();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ledger_L1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('statement_button')));
      await tester.pumpAndSettle();

      String row(String key) => [
        for (final e
            in find
                .descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(Text),
                )
                .evaluate())
          (e.widget as Text).data ?? '',
      ].join(' | ');

      expect(find.text('كشف حساب سعد'), findsOneWidget);
      expect(row('statement_opening'), 'الرصيد السابق | 100 ر.س لك');
      expect(find.byKey(Key('statement_line_${paid.id}')), findsOneWidget);
      expect(row('statement_closing'), 'الرصيد النهائي | 70 ر.س لك');
      expect(find.byKey(const Key('statement_unconfirmed')), findsOneWidget);

      await tester.tap(find.byKey(const Key('statement_all')));
      await tester.pumpAndSettle();
      expect(row('statement_opening'), 'الرصيد السابق | 0 ر.س');
      expect(row('statement_closing'), 'الرصيد النهائي | 70 ر.س لك');

      await tester.tap(find.byKey(const Key('copy_statement_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('نُسخ الكشف. أرسله عبر واتساب أو رسالة.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('copy_csv_button')));
      await tester.pumpAndSettle();
      final all = buildStatement(
        ledger(),
        ledgers.entries['L1']!,
        from: null,
        to: today,
      );
      expect(clipboard, [statementText(all), statementCsv(all)]);
    });
  });
}
