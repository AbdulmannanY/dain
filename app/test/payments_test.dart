import 'dart:math';

import 'package:dain/app.dart';
import 'package:dain/core/ids.dart';
import 'package:dain/core/money.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/ledgers/ledger_controller.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

LedgerSummary ledger({bool owner = true, int confirmed = 10000}) =>
    LedgerSummary(
      id: 'L1',
      iAmOwner: owner,
      title: owner ? 'سعد' : 'بقالة النور',
      subtitle: null,
      currency: 'SAR',
      myConfirmedMinor: confirmed,
      myOpenMinor: confirmed,
      pendingCount: 0,
      disputedCount: 0,
      otherPartyJoined: true,
    );

LedgerEntry entry(
  int delta, {
  bool payment = true,
  EntryStatus status = EntryStatus.pending,
}) => LedgerEntry(
  id: 'x$delta${status.name}',
  myDeltaMinor: delta,
  note: null,
  occurredOn: DateTime(2026, 10, 20),
  status: status,
  createdByMe: false,
  responseNote: null,
  isPayment: payment,
);

void main() {
  group('paymentRoomOf', () {
    test('they owe me: less their payments pending or disputed', () {
      expect(paymentRoomOf(ledger(), const []), 10000);
      expect(
        paymentRoomOf(ledger(), [
          entry(-3000),
          entry(-1000, status: EntryStatus.disputed),
          // not held: answered, withdrawn, a debt, or my own payment
          entry(-500, status: EntryStatus.confirmed),
          entry(-700, status: EntryStatus.voided),
          entry(-900, payment: false),
          entry(400),
        ]),
        6000,
      );
    });

    test('I owe: less my payments; nothing owed or all held is zero', () {
      expect(paymentRoomOf(ledger(confirmed: -5000), [entry(2000)]), 3000);
      expect(paymentRoomOf(ledger(confirmed: -5000), [entry(-2000)]), 5000);
      expect(paymentRoomOf(ledger(confirmed: 0), const []), 0);
      expect(paymentRoomOf(ledger(), [entry(-12000)]), 0);
    });
  });

  test('newEntryId: a random version-4 UUID', () {
    final ids = {for (var i = 0; i < 500; i++) newEntryId()};
    expect(ids, hasLength(500));
    final v4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(ids.every(v4.hasMatch), isTrue);
    expect(newEntryId(Random(1)), newEntryId(Random(1)));
  });

  test('plainAmount is what parseMoney reads back', () {
    for (final minor in [1, 99, 100, 4550, 500000, 12345678901]) {
      expect(parseMoney(plainAmount(minor)), minor, reason: '$minor');
    }
    expect(plainAmount(4550), '45.50');
    expect(plainAmount(-500000), '5000');
  });

  test('buildEntries reads the kind', () {
    final rows = [
      for (final kind in ['payment', 'debt'])
        {
          'id': kind,
          'direction': 'in',
          'amount_minor': 100,
          'note': null,
          'occurred_on': '2026-10-21',
          'status': 'pending',
          'response_note': null,
          'created_by': 'cp',
          'kind': kind,
        },
    ];
    final built = buildEntries(rows, iAmOwner: true, myId: 'me');
    expect(built.map((e) => e.isPayment), [true, false]);
  });

  group('on the ledger screen', () {
    late FakeLedgers ledgers;

    Future<void> open(WidgetTester tester, LedgerSummary l) async {
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
      await tester.tap(find.byKey(const Key('ledger_L1')));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    String amountText(WidgetTester tester) => tester
        .widget<TextField>(find.byKey(const Key('amount_field')))
        .controller!
        .text;

    Finder inEntry(String id, String text) => find.descendant(
      of: find.byKey(Key('entry_$id')),
      matching: find.textContaining(text),
    );

    testWidgets('they owe me: I record part of a payment, the rest is left', (
      tester,
    ) async {
      await open(tester, ledger());
      expect(
        find.descendant(
          of: find.byKey(const Key('record_payment_button')),
          matching: find.text('استلمت سداداً'),
        ),
        findsOneWidget,
      );

      await tap(tester, 'record_payment_button');
      // Filled in with all that is left.
      expect(amountText(tester), '100');
      await tester.enterText(find.byKey(const Key('amount_field')), '40');
      await tap(tester, 'save_entry_button');

      // The owner received it: the counterparty gave, stored 'in'.
      expect(ledgers.added.single.$2, 'in');
      expect(ledgers.added.single.$3, 4000);
      expect(ledgers.addedPayments, [true]);
      expect(
        find.text('سُجّل السداد. ينتظر تأكيد الطرف الآخر.'),
        findsOneWidget,
      );
      expect(inEntry('e1', 'استلمت سداداً 40 ر.س'), findsOneWidget);

      // The pending 40 holds its part: 60 is left to record.
      await tap(tester, 'record_payment_button');
      expect(amountText(tester), '60');
      await tester.enterText(find.byKey(const Key('amount_field')), '61');
      await tap(tester, 'save_entry_button');
      expect(find.text('السداد أكبر من المتبقي (60 ر.س).'), findsOneWidget);
      expect(ledgers.added, hasLength(1));
    });

    testWidgets('I owe: I record paying it all; then nothing is left to pay', (
      tester,
    ) async {
      await open(tester, ledger(owner: false, confirmed: -5000));
      expect(
        find.descendant(
          of: find.byKey(const Key('record_payment_button')),
          matching: find.text('سدّدت'),
        ),
        findsOneWidget,
      );
      await tap(tester, 'record_payment_button');
      await tap(tester, 'save_entry_button');

      // The counterparty gave: stored 'in', for the whole 50.
      expect(ledgers.added.single.$2, 'in');
      expect(ledgers.added.single.$3, 5000);
      expect(inEntry('e1', 'سدّدت 50 ر.س'), findsOneWidget);
      expect(find.byKey(const Key('record_payment_button')), findsNothing);
    });

    testWidgets('no agreed balance: no payment to record', (tester) async {
      await open(tester, ledger(confirmed: 0));
      expect(find.byKey(const Key('record_payment_button')), findsNothing);
    });

    testWidgets('a save whose answer was lost is sent again once, not twice', (
      tester,
    ) async {
      await open(tester, ledger());
      await tap(tester, 'record_payment_button');
      await tester.enterText(find.byKey(const Key('amount_field')), '25');
      ledgers.loseNextAnswer = true;
      await tap(tester, 'save_entry_button');
      // Saved in the database, but the phone did not hear back.
      expect(find.text('لا يوجد اتصال بالإنترنت.'), findsOneWidget);
      expect(ledgers.added, hasLength(1));

      // Again, same entry: the same id comes back as 23505 = already saved.
      await tap(tester, 'save_entry_button');
      expect(find.byKey(const Key('save_entry_button')), findsNothing);
      expect(ledgers.added, hasLength(1));
      expect(find.byKey(const Key('entry_e1')), findsOneWidget);
      expect(find.byKey(const Key('entry_e2')), findsNothing);
    });
  });

  group('the controller', () {
    test('the same entry keeps its id; a changed one gets a new id', () async {
      final repo = FakeLedgers([ledger()]);
      var n = 0;
      final c = LedgerController(repo, 'L1', newId: () => 'id${++n}');
      await c.load();

      repo.failNextAddWith = Exception('SocketException: timeout');
      expect(await c.addEntry(iGave: true, amount: '5'), isFalse);
      expect(await c.addEntry(iGave: true, amount: '5'), isTrue);
      expect(repo.sentIds, ['id1']);

      expect(await c.addEntry(iGave: true, amount: '5'), isTrue);
      expect(repo.sentIds, ['id1', 'id2'], reason: 'a new entry after a save');

      repo.failNextAddWith = Exception('SocketException: timeout');
      expect(await c.addEntry(iGave: true, amount: '7'), isFalse);
      expect(await c.addEntry(iGave: true, amount: '8'), isTrue);
      expect(repo.sentIds, ['id1', 'id2', 'id4']);
    });

    test(
      'the database refusing a payment (23514) reloads the ledger',
      () async {
        final repo = FakeLedgers([ledger()]);
        final c = LedgerController(repo, 'L1');
        await c.load();
        // The other side answered meanwhile: less is owed than shown.
        repo.ledgers = [ledger(confirmed: 3000)];
        repo.failNextAddWith = const PostgrestException(
          message: 'payment exceeds what is owed (3000)',
          code: '23514',
        );
        expect(await c.recordPayment(amount: '50'), isFalse);
        expect(c.formError, LedgerController.overpaidReloaded);
        expect(c.ledger!.myConfirmedMinor, 3000);
        expect(c.paymentRoom, 3000);
      },
    );

    test('no agreed balance: refused before saving', () async {
      final repo = FakeLedgers([ledger(confirmed: 0)]);
      final c = LedgerController(repo, 'L1');
      await c.load();
      expect(await c.recordPayment(amount: '1'), isFalse);
      expect(c.formError, 'لا رصيد متفق عليه لسداده.');
      expect(repo.added, isEmpty);
    });
  });
}
