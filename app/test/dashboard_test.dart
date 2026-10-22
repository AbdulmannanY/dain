import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/ledgers/dashboard_controller.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

LedgerSummary summary(
  String id,
  String title,
  int confirmed, {
  String currency = 'SAR',
  bool owner = true,
  DateTime? dueOn,
}) => LedgerSummary(
  id: id,
  iAmOwner: owner,
  title: title,
  subtitle: null,
  currency: currency,
  myConfirmedMinor: confirmed,
  myOpenMinor: confirmed,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: true,
  dueOn: dueOn,
);

LedgerFlow paid(String ledger, int myDelta, DateTime on, {int count = 1}) =>
    LedgerFlow(
      ledgerId: ledger,
      status: EntryStatus.confirmed,
      myDeltaMinor: myDelta,
      count: count,
      paidOn: on,
    );

LedgerFlow open(String ledger, EntryStatus status, int myDelta, int count) =>
    LedgerFlow(
      ledgerId: ledger,
      status: status,
      myDeltaMinor: myDelta,
      count: count,
    );

final today = DateTime(2026, 10, 22);
DateTime ago(int days) => DateTime(2026, 10, 22 - days);

CurrencyDashboard only(
  List<LedgerSummary> ledgers, {
  List<LedgerFlow> flows = const [],
  DashboardPeriod period = DashboardPeriod.month,
}) => buildDashboards(
  ledgers: ledgers,
  flows: flows,
  period: period,
  today: today,
).single;

void main() {
  group('the dashboard of each currency', () {
    test('currencies stay apart, balances from my side', () {
      final all = buildDashboards(
        ledgers: [
          summary('1', 'سعد', 50000),
          summary('2', 'بقالة', -20000, owner: false),
          summary('3', 'علي', 30000),
          summary('4', 'محمد', 550000, currency: 'YER'),
        ],
        flows: const [],
        period: DashboardPeriod.month,
        today: today,
      );
      expect([for (final d in all) d.currency], ['SAR', 'YER']);
      expect((all[0].owedToMeMinor, all[0].iOweMinor), (80000, 20000));
      expect((all[1].owedToMeMinor, all[1].iOweMinor), (550000, 0));
    });

    test('collected and paid count confirmed payments in the period only', () {
      final ledgers = [summary('1', 'سعد', 1000)];
      final flows = [
        paid('1', -3000, today, count: 2), // I was paid today
        paid('1', 1000, ago(6)), // I paid, 6 days ago
        paid('1', -700, ago(7)),
        paid('1', -400, ago(29)),
        paid('1', -999, ago(30)),
        paid('1', -50, DateTime(2026, 10, 23)), // tomorrow
      ];
      final day = only(ledgers, flows: flows, period: DashboardPeriod.day);
      final week = only(ledgers, flows: flows, period: DashboardPeriod.week);
      final month = only(ledgers, flows: flows);
      expect((day.collectedMinor, day.paidMinor), (3000, 0));
      expect((week.collectedMinor, week.paidMinor), (3000, 1000));
      expect((month.collectedMinor, month.paidMinor), (4100, 1000));
      // Payments do not touch the agreed balance shown beside them.
      expect(month.owedToMeMinor, 1000);
    });

    test(
      'pending and disputed add up their amounts, apart from the balance',
      () {
        final d = only(
          [summary('1', 'سعد', 1000), summary('2', 'علي', -500)],
          flows: [
            open('1', EntryStatus.pending, 700, 1),
            open('1', EntryStatus.pending, -1000, 2),
            open('2', EntryStatus.disputed, 500, 1),
          ],
        );
        expect((d.pendingMinor, d.pendingCount), (1700, 3));
        expect((d.disputedMinor, d.disputedCount), (500, 1));
        expect((d.owedToMeMinor, d.iOweMinor), (1000, 500));
        expect((d.collectedMinor, d.paidMinor), (0, 0));
      },
    );

    test('overdue and due soon, owed to me and by me', () {
      final d = only([
        summary('1', 'أ', 1000, dueOn: ago(1)),
        summary('2', 'ب', -300, dueOn: ago(1)),
        summary('3', 'ج', 200, dueOn: today),
        summary('4', 'د', -150, dueOn: DateTime(2026, 10, 29)),
        summary('5', 'ه', 100, dueOn: DateTime(2026, 10, 30)),
        summary('6', 'و', 0, dueOn: ago(1)),
        summary('7', 'ز', 5000),
      ]);
      expect((d.overdueToMeMinor, d.overdueIOweMinor), (1000, 300));
      expect((d.dueSoonToMeMinor, d.dueSoonIOweMinor), (200, 150));
    });

    test('the three ledgers that owe me most, largest first', () {
      final d = only([
        summary('1', 'أ', 100),
        summary('2', 'ب', 900),
        summary('3', 'ج', -5000),
        summary('4', 'د', 400),
        summary('5', 'ه', 700),
        summary('6', 'و', 0),
      ]);
      expect([for (final l in d.topDebtors) l.title], ['ب', 'ه', 'د']);
    });

    test('flows are turned to my side, and an unknown ledger is left out', () {
      final rows = [
        {
          'ledger_id': 'mine',
          'status': 'confirmed',
          'direction': 'in',
          'paid_on': '2026-10-21',
          'amount_minor': 3000,
          'entry_count': 1,
        },
        {
          'ledger_id': 'theirs',
          'status': 'confirmed',
          'direction': 'in',
          'paid_on': '2026-10-21',
          'amount_minor': 3000,
          'entry_count': 1,
        },
        {
          'ledger_id': 'theirs',
          'status': 'pending',
          'direction': 'out',
          'paid_on': null,
          'amount_minor': 700,
          'entry_count': 2,
        },
        {
          'ledger_id': 'gone',
          'status': 'pending',
          'direction': 'out',
          'paid_on': null,
          'amount_minor': 1,
          'entry_count': 1,
        },
      ];
      final flows = buildFlows(
        rows,
        ledgers: [
          summary('mine', 'سعد', 0),
          summary('theirs', 'بقالة', 0, owner: false),
        ],
      );
      expect(flows, hasLength(3));
      // The other party paid me (owner): I was paid.
      expect(flows[0].myDeltaMinor, -3000);
      expect(flows[0].paidOn, DateTime(2026, 10, 21));
      // I am the other party and I paid: positive.
      expect(flows[1].myDeltaMinor, 3000);
      expect(
        (flows[2].status, flows[2].myDeltaMinor, flows[2].count),
        (EntryStatus.pending, -700, 2),
      );
      expect(flows[2].paidOn, isNull);
    });
  });

  group('the dashboard screen', () {
    late FakeAuth auth;
    late FakeProfiles profiles;
    late FakeLedgers ledgers;

    setUp(() {
      auth = FakeAuth(signedInAs: '966500000001');
      profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
      ledgers = FakeLedgers();
    });

    DateTime now() {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day);
    }

    DateTime daysAgo(int days) {
      final n = now();
      return DateTime(n.year, n.month, n.day - days);
    }

    Future<void> openDashboard(WidgetTester tester) async {
      // Phone-sized screen: overflow would fail the test.
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = SessionController(auth: auth, profiles: profiles);
      await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
      await c.start();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard_button')));
      await tester.pumpAndSettle();
    }

    String line(String key) => textsIn(find.byKey(Key(key))).join(' | ');

    testWidgets('each currency apart, and the period changes the payments', (
      tester,
    ) async {
      ledgers.ledgers = [
        summary('1', 'سعد', 45000),
        summary('2', 'بقالة النور', -12000, owner: false),
        summary('3', 'محمد', 550000, currency: 'YER'),
      ];
      ledgers.flows = [
        paid('1', -5000, now()),
        paid('1', -2000, daysAgo(3)),
        paid('2', 1500, daysAgo(20)),
        paid('1', -9900, daysAgo(31)), // before the month: never asked for
        open('1', EntryStatus.pending, 700, 1),
        open('2', EntryStatus.disputed, -300, 1),
      ];
      await openDashboard(tester);

      expect(find.text('الملخص المالي'), findsOneWidget);
      expect(ledgers.flowsSince, [daysAgo(29)]);
      expect(line('owed_to_me_SAR'), 'لك (متفق عليه) | 450 ر.س');
      expect(line('i_owe_SAR'), 'عليك (متفق عليه) | 120 ر.س');
      expect(line('collected_SAR'), 'المحصَّل في الفترة | 70 ر.س');
      expect(line('paid_SAR'), 'المدفوع في الفترة | 15 ر.س');
      expect(line('pending_SAR'), 'بانتظار التأكيد (1) | 7 ر.س');
      expect(line('disputed_SAR'), 'معترض عليه (1) | 3 ر.س');
      // Rials of Yemen on their own card, never added to riyals.
      expect(line('owed_to_me_YER'), 'لك (متفق عليه) | 5,500 ر.ي');
      expect(line('collected_YER'), 'المحصَّل في الفترة | 0 ر.ي');
      expect(find.byKey(const Key('debtor_1')), findsOneWidget);
      expect(find.byKey(const Key('debtor_2')), findsNothing);

      await tester.tap(find.byKey(const Key('period_week')));
      await tester.pumpAndSettle();
      expect(line('collected_SAR'), 'المحصَّل في الفترة | 70 ر.س');
      expect(line('paid_SAR'), 'المدفوع في الفترة | 0 ر.س');

      await tester.tap(find.byKey(const Key('period_day')));
      await tester.pumpAndSettle();
      expect(line('collected_SAR'), 'المحصَّل في الفترة | 50 ر.س');
      // Choosing a period reads nothing again.
      expect(ledgers.flowsSince, hasLength(1));
    });

    testWidgets('a failed load says why, and retrying loads it', (
      tester,
    ) async {
      ledgers.ledgers = [summary('1', 'سعد', 45000)];
      ledgers.failFlowsWith = const PostgrestException(message: 'boom');
      await openDashboard(tester);
      expect(find.text('تعذّر إتمام العملية. حاول مجدداً.'), findsOneWidget);

      ledgers.failFlowsWith = null;
      await tester.tap(find.byKey(const Key('retry_button')));
      await tester.pumpAndSettle();
      expect(line('owed_to_me_SAR'), 'لك (متفق عليه) | 450 ر.س');
    });

    testWidgets('a debtor opens its ledger, and coming back reloads', (
      tester,
    ) async {
      ledgers.ledgers = [summary('1', 'سعد', 45000)];
      await openDashboard(tester);
      final before = ledgers.fetches;

      await tester.tap(find.byKey(const Key('debtor_1')));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byKey(const Key('dashboard_list')), findsNothing);

      ledgers.ledgers = [summary('1', 'سعد', 40000)];
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(ledgers.fetches, greaterThan(before));
      expect(line('owed_to_me_SAR'), 'لك (متفق عليه) | 400 ر.س');
    });

    testWidgets('no ledgers yet: says so', (tester) async {
      await openDashboard(tester);
      expect(find.byKey(const Key('dashboard_empty')), findsOneWidget);
      expect(find.byKey(const Key('period_day')), findsNothing);
    });
  });
}

/// The texts under [finder], in order.
List<String> textsIn(Finder finder) => [
  for (final e
      in find.descendant(of: finder, matching: find.byType(Text)).evaluate())
    (e.widget as Text).data ?? '',
];
