import 'package:dain/core/money.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const me = 'me';
const other = 'other';

Map<String, dynamic> ledgerRow(
  String id, {
  String owner = me,
  String? counterparty = other,
  String name = 'سعد',
  String? shop,
  String ownerName = 'أحمد',
  String currency = 'SAR',
}) => {
  'id': id,
  'owner_id': owner,
  'counterparty_id': counterparty,
  'counterparty_name': name,
  'currency': currency,
  'business': shop == null ? null : {'name': shop},
  'owner': {'full_name': ownerName},
};

Map<String, dynamic> balanceRow(
  String id, {
  int confirmed = 0,
  int open = 0,
  int pending = 0,
  int disputed = 0,
}) => {
  'ledger_id': id,
  'confirmed_balance_minor': confirmed,
  'open_balance_minor': open,
  'pending_count': pending,
  'disputed_count': disputed,
};

void main() {
  group('buildSummaries', () {
    test('owner sees the stored sign; counterparty sees it flipped', () {
      final rows = [
        ledgerRow('L1'), // I own it: positive = they owe me
        ledgerRow('L2', owner: other, counterparty: me, ownerName: 'بدر'),
      ];
      final balances = [
        balanceRow('L1', confirmed: 5000, open: 7000, pending: 1),
        balanceRow('L2', confirmed: 3000, open: 3000),
      ];
      final s = {
        for (final l in buildSummaries(
          ledgerRows: rows,
          balanceRows: balances,
          myId: me,
        ))
          l.id: l,
      };

      expect(s['L1']!.iAmOwner, isTrue);
      expect(s['L1']!.myConfirmedMinor, 5000);
      expect(s['L1']!.myOpenMinor, 7000);
      expect(s['L1']!.pendingCount, 1);
      expect(s['L1']!.title, 'سعد');

      // L2: the other person owns it and I owe them 30.00.
      expect(s['L2']!.iAmOwner, isFalse);
      expect(s['L2']!.myConfirmedMinor, -3000);
      expect(s['L2']!.title, 'بدر', reason: 'counterparty sees the owner');
    });

    test(
      'shop ledgers: shop is the subtitle for the owner, title for the customer',
      () {
        final s = buildSummaries(
          ledgerRows: [
            ledgerRow('mine', shop: 'بقالة النور'),
            ledgerRow(
              'theirs',
              owner: other,
              counterparty: me,
              shop: 'صيدلية الشفاء',
              ownerName: 'خالد',
            ),
          ],
          balanceRows: const [],
          myId: me,
        );
        final mine = s.singleWhere((l) => l.id == 'mine');
        final theirs = s.singleWhere((l) => l.id == 'theirs');
        expect((mine.title, mine.subtitle), ('سعد', 'بقالة النور'));
        expect((theirs.title, theirs.subtitle), ('صيدلية الشفاء', 'خالد'));
      },
    );

    test(
      'a counterparty who has not signed in yet is flagged for the owner',
      () {
        final s = buildSummaries(
          ledgerRows: [ledgerRow('L', counterparty: null)],
          balanceRows: const [],
          myId: me,
        );
        expect(s.single.otherPartyJoined, isFalse);
      },
    );

    test('missing balance row counts as zero', () {
      final s = buildSummaries(
        ledgerRows: [ledgerRow('L')],
        balanceRows: const [],
        myId: me,
      );
      expect(s.single.myConfirmedMinor, 0);
      expect(s.single.pendingCount, 0);
    });

    test('largest agreed balance first, whichever side', () {
      final s = buildSummaries(
        ledgerRows: [
          ledgerRow('small', name: 'ب'),
          ledgerRow('big-debt', name: 'أ'),
          ledgerRow('zero', name: 'ج'),
        ],
        balanceRows: [
          balanceRow('small', confirmed: 100),
          balanceRow('big-debt', confirmed: -900),
        ],
        myId: me,
      );
      expect(s.map((l) => l.id), ['big-debt', 'small', 'zero']);
    });
  });

  test('totalsByCurrency splits what I am owed from what I owe', () {
    LedgerSummary l(int v, [String c = 'SAR']) => LedgerSummary(
      id: '$v$c',
      iAmOwner: true,
      title: 't',
      subtitle: null,
      currency: c,
      myConfirmedMinor: v,
      myOpenMinor: v,
      pendingCount: 0,
      disputedCount: 0,
      otherPartyJoined: true,
    );
    final t = totalsByCurrency([
      l(5000),
      l(2500),
      l(-1200),
      l(0),
      l(700, 'USD'),
    ]);
    expect(t.map((x) => (x.currency, x.owedToMeMinor, x.iOweMinor)), [
      ('SAR', 7500, 1200),
      ('USD', 700, 0),
    ]);
  });

  test('formatMoney', () {
    expect(formatMoney(4550, 'SAR'), '45.50 ر.س');
    expect(formatMoney(-4550, 'SAR'), '45.50 ر.س');
    expect(formatMoney(500000, 'SAR'), '5,000 ر.س');
    expect(formatMoney(123456789, 'SAR'), '1,234,567.89 ر.س');
    expect(formatMoney(5, 'SAR'), '0.05 ر.س');
    expect(formatMoney(100, 'USD'), '1 USD');
  });
}
