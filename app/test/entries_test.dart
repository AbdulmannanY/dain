import 'package:dain/core/money.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> entryRow(
  String id,
  String direction,
  int amount, {
  String status = 'pending',
  String createdBy = 'owner',
  String? note,
  String? responseNote,
}) => {
  'id': id,
  'direction': direction,
  'amount_minor': amount,
  'note': note,
  'occurred_on': '2026-10-21',
  'status': status,
  'response_note': responseNote,
  'created_by': createdBy,
};

void main() {
  test('entryDirection: stored relative to the owner', () {
    // owner gave -> out ; owner took -> in
    expect(entryDirection(iAmOwner: true, iGave: true), 'out');
    expect(entryDirection(iAmOwner: true, iGave: false), 'in');
    // counterparty gave the owner -> in ; counterparty took -> out
    expect(entryDirection(iAmOwner: false, iGave: true), 'in');
    expect(entryDirection(iAmOwner: false, iGave: false), 'out');
  });

  group('buildEntries', () {
    final rows = [
      entryRow('1', 'out', 10000, status: 'confirmed', note: 'أرز'),
      entryRow('2', 'in', 3000, createdBy: 'cp', responseNote: 'تم'),
      entryRow('3', 'out', 500, status: 'voided'),
    ];

    test('owner sees the stored sign', () {
      final e = buildEntries(rows, iAmOwner: true, myId: 'owner');
      expect(e.map((x) => x.myDeltaMinor), [10000, -3000, 500]);
      expect(e.map((x) => x.createdByMe), [true, false, true]);
      expect(e.map((x) => x.status), [
        EntryStatus.confirmed,
        EntryStatus.pending,
        EntryStatus.voided,
      ]);
      expect(e.first.note, 'أرز');
      expect(e[1].responseNote, 'تم');
      expect(e.first.occurredOn, DateTime(2026, 10, 21));
    });

    test('counterparty sees it flipped and its own entries as mine', () {
      final e = buildEntries(rows, iAmOwner: false, myId: 'cp');
      expect(e.map((x) => x.myDeltaMinor), [-10000, 3000, -500]);
      expect(e.map((x) => x.createdByMe), [false, true, false]);
    });

    test('recording then reading gives back what I typed, on both sides', () {
      for (final owner in [true, false]) {
        for (final gave in [true, false]) {
          final row = entryRow(
            'x',
            entryDirection(iAmOwner: owner, iGave: gave),
            700,
          );
          final e = buildEntries([row], iAmOwner: owner, myId: 'owner');
          expect(e.single.myDeltaMinor, gave ? 700 : -700);
        }
      }
    });
  });

  test('entryActions mirror respond_entry and void_entry', () {
    Set<EntryAction> of(EntryStatus status, {required bool mine}) =>
        entryActions(
          LedgerEntry(
            id: 'x',
            myDeltaMinor: 1,
            note: null,
            occurredOn: DateTime(2026),
            status: status,
            createdByMe: mine,
            responseNote: null,
          ),
        );
    const c = EntryAction.confirm, d = EntryAction.dispute;
    const w = EntryAction.withdraw;
    expect(of(EntryStatus.pending, mine: false), {c, d});
    expect(of(EntryStatus.disputed, mine: false), {c});
    expect(of(EntryStatus.confirmed, mine: false), isEmpty);
    expect(of(EntryStatus.voided, mine: false), isEmpty);
    expect(of(EntryStatus.pending, mine: true), {w});
    expect(of(EntryStatus.disputed, mine: true), {w});
    expect(of(EntryStatus.confirmed, mine: true), isEmpty);
    expect(of(EntryStatus.voided, mine: true), isEmpty);
  });

  test('isoDay', () {
    expect(isoDay(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
  });

  test('parseMoney', () {
    expect(parseMoney('45.5'), 4550);
    expect(parseMoney(' 45.50 '), 4550);
    expect(parseMoney('٤٥٫٥'), 4550);
    expect(parseMoney('۴۵'), 4500);
    expect(parseMoney('5,000'), 500000);
    expect(parseMoney('٥٬٠٠٠'), 500000);
    expect(parseMoney('0.01'), 1);
    expect(parseMoney('1000000000'), maxAmountMinor);
    for (final bad in [
      '',
      '0',
      '0.00',
      '-5',
      '1.234',
      '.5',
      '5.',
      'abc',
      '1e3',
      '1000000000.01',
      '9999999999999',
    ]) {
      expect(parseMoney(bad), isNull, reason: bad);
    }
  });
}
