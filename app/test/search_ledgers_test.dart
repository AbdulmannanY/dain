import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/ledgers/ledgers_controller.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

LedgerSummary summary(
  String id,
  String title,
  int confirmed, {
  String? subtitle,
  String? phone,
  int pending = 0,
  int disputed = 0,
}) => LedgerSummary(
  id: id,
  iAmOwner: phone != null,
  title: title,
  subtitle: subtitle,
  currency: 'SAR',
  myConfirmedMinor: confirmed,
  myOpenMinor: confirmed,
  pendingCount: pending,
  disputedCount: disputed,
  otherPartyJoined: true,
  counterpartyPhone: phone,
);

// As buildSummaries returns them: the largest agreed balance first.
final _all = [
  summary('1', 'أحمد علي', 90000, phone: '966500000001'),
  summary('2', 'بقالة النور', -50000, subtitle: 'خالد', pending: 1),
  summary('3', 'فاطمة', 20000, phone: '967771234567', disputed: 2),
  summary('4', 'سعد', 0, phone: '966500000009', pending: 1),
];

List<String> ids(List<LedgerSummary> l) => [for (final x in l) x.id];

void main() {
  test('searchKey folds hamza, taa marbuta, alef maqsura, marks, digits', () {
    expect(searchKey('أحمد'), searchKey('احمد'));
    expect(searchKey('إيمان آمنة'), 'ايمان امنه');
    expect(searchKey('مُصْطَفَى'), 'مصطفي');
    expect(searchKey('مـحـمد'), 'محمد');
    expect(searchKey('٠٥٠٠ ۱۲'), '0500 12');
    expect(searchKey('Ali'), 'ali');
  });

  group('searchLedgers', () {
    List<String> find(String q, [LedgerSort s = LedgerSort.balance]) =>
        ids(searchLedgers(_all, query: q, sort: s));

    test('an empty query keeps every ledger in the loaded order', () {
      expect(find(''), ['1', '2', '3', '4']);
      expect(find('   '), ['1', '2', '3', '4']);
    });

    test('by name, spelled loosely, every word anywhere', () {
      expect(find('احمد'), ['1']);
      expect(find('فاطمه'), ['3']);
      expect(find('علي احمد'), ['1']);
      expect(find('احمد سعد'), isEmpty);
    });

    test('by the shop or the owner under it', () {
      expect(find('النور'), ['2']);
      expect(find('خالد'), ['2']);
    });

    test('by the number, local or international, in any digits', () {
      expect(find('0500000009'), ['4']);
      expect(find('٧٧١٢٣'), ['3']);
      expect(find('+966 50 000 0001'), ['1']);
      expect(find('9665'), ['1', '4']);
      // One digit is too little to mean a number.
      expect(find('5'), isEmpty);
    });

    test('sorted by name, or with open entries first', () {
      expect(find('', LedgerSort.name), ['1', '2', '4', '3']);
      // 3 has two disputed; 2 and 4 one pending each keep their order.
      expect(find('', LedgerSort.open), ['3', '2', '4', '1']);
    });
  });

  group('in «دفاتري»', () {
    late FakeLedgers ledgers;

    Future<void> launch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = FakeAuth(signedInAs: '966500000001');
      final profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
      ledgers = FakeLedgers(_all);
      final c = SessionController(auth: auth, profiles: profiles);
      await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
      await c.start();
      await tester.pumpAndSettle();
    }

    List<String> shown(WidgetTester tester) {
      final tiles = [
        for (final l in _all)
          if (find.byKey(Key('ledger_${l.id}')).evaluate().isNotEmpty) l.id,
      ];
      double y(String id) =>
          tester.getTopLeft(find.byKey(Key('ledger_$id'))).dy;
      return tiles..sort((a, b) => y(a).compareTo(y(b)));
    }

    testWidgets('typing filters, clearing brings every ledger back', (
      tester,
    ) async {
      await launch(tester);
      expect(shown(tester), ['1', '2', '3', '4']);

      await tester.enterText(
        find.byKey(const Key('ledger_search_field')),
        'فاطمه',
      );
      await tester.pumpAndSettle();
      expect(shown(tester), ['3']);
      // The totals still cover every ledger.
      expect(
        find.descendant(
          of: find.byKey(const Key('total_owed_to_me_SAR')),
          matching: find.text('1,100 ر.س'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('ledger_search_field')),
        'زيد',
      );
      await tester.pumpAndSettle();
      expect(shown(tester), isEmpty);
      expect(find.text('لا دفتر يطابق «زيد».'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clear_search_button')));
      await tester.pumpAndSettle();
      expect(shown(tester), ['1', '2', '3', '4']);
      expect(find.byKey(const Key('search_empty')), findsNothing);
    });

    testWidgets('the chips change the order; a refresh keeps the search', (
      tester,
    ) async {
      await launch(tester);
      await tester.tap(find.byKey(const Key('sort_open')));
      await tester.pumpAndSettle();
      expect(shown(tester), ['3', '2', '4', '1']);
      await tester.tap(find.byKey(const Key('sort_name')));
      await tester.pumpAndSettle();
      expect(shown(tester), ['1', '2', '4', '3']);

      await tester.enterText(
        find.byKey(const Key('ledger_search_field')),
        '0500',
      );
      await tester.pumpAndSettle();
      expect(shown(tester), ['1', '4']);
      await tester.fling(
        find.byKey(const Key('ledgers_list')),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(ledgers.fetches, 2);
      expect(shown(tester), ['1', '4']);
    });
  });
}
