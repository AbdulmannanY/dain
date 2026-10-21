import 'package:dain/app.dart';
import 'package:dain/core/config.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

LedgerSummary ledger({required bool owner}) => LedgerSummary(
  id: 'L1',
  iAmOwner: owner,
  title: 'سعد',
  subtitle: null,
  currency: 'SAR',
  myConfirmedMinor: 0,
  myOpenMinor: 0,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: false,
);

/// The owner's share link, from the ledger's screen of the real DainApp.
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late FakeLedgers ledgers;
  late List<String> clipboard;

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers();
    clipboard = [];
  });

  Future<void> openLedger(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  testWidgets('the owner creates a link, copies it, replaces and stops it', (
    tester,
  ) async {
    ledgers.ledgers = [ledger(owner: true)];
    await openLedger(tester);
    await tap(tester, 'share_link_button');
    expect(find.byKey(const Key('share_link_text')), findsNothing);

    await tap(tester, 'create_link_button');
    final first = DainConfig.shareUrl('tok1');
    expect(first, 'https://abdulmannany.github.io/dain/#tok1');
    expect(ledgers.shareLinks, {'L1': 'tok1'});
    expect(clipboard, [first]);
    expect(find.text(first), findsOneWidget);
    expect(find.byKey(const Key('share_link_copied')), findsOneWidget);

    // A new link replaces the old one.
    await tap(tester, 'create_link_button');
    expect(ledgers.shareLinks, {'L1': 'tok2'});
    expect(clipboard.last, DainConfig.shareUrl('tok2'));

    await tap(tester, 'revoke_link_button');
    expect(ledgers.shareLinks, isEmpty);
    expect(find.byKey(const Key('share_link_text')), findsNothing);
  });

  testWidgets('the other party has no share button', (tester) async {
    ledgers.ledgers = [ledger(owner: false)];
    await openLedger(tester);
    expect(find.byKey(const Key('share_link_button')), findsNothing);
  });
}
