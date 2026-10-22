import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

LedgerSummary summary(String id, String title, int confirmed) => LedgerSummary(
  id: id,
  iAmOwner: true,
  title: title,
  subtitle: null,
  currency: 'SAR',
  myConfirmedMinor: confirmed,
  myOpenMinor: confirmed,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: true,
);

/// Leaving the app and coming back, through the states Flutter reports.
Future<void> leaveAndReturn(WidgetTester tester) async {
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

void main() {
  late FakeLedgers ledgers;

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeAuth(signedInAs: '966500000001');
    final profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers([summary('1', 'سعد', 100)]);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
  }

  testWidgets('back in the app, the list shows what changed meanwhile', (
    tester,
  ) async {
    await launch(tester);
    expect(ledgers.fetches, 1);

    ledgers.ledgers = [summary('1', 'سعد', 100), summary('2', 'بدر', -50)];
    await leaveAndReturn(tester);
    expect(ledgers.fetches, 2);
    expect(find.byKey(const Key('ledger_2')), findsOneWidget);
  });

  testWidgets('on a ledger, it reloads; the list waits until it is shown', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byKey(const Key('ledger_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entries_empty')), findsOneWidget);

    // The other party recorded an entry while I was away.
    ledgers.entries['1'] = [
      LedgerEntry(
        id: 'x',
        myDeltaMinor: -700,
        note: null,
        occurredOn: DateTime(2026, 10, 20),
        status: EntryStatus.pending,
        createdByMe: false,
        responseNote: null,
      ),
    ];
    final before = ledgers.fetches;
    await leaveAndReturn(tester);
    expect(find.byKey(const Key('entry_x')), findsOneWidget);
    expect(ledgers.fetches, before, reason: 'the list is not on screen');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(ledgers.fetches, before + 1);
  });
}
