import 'package:dain/app.dart';
import 'package:dain/core/config.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

LedgerSummary ledger({
  bool owner = true,
  int confirmed = 4550,
  int? every,
  DateTime? last,
  String? shop,
}) => LedgerSummary(
  id: 'L1',
  iAmOwner: owner,
  title: 'سعد',
  subtitle: shop,
  currency: 'SAR',
  myConfirmedMinor: confirmed,
  myOpenMinor: confirmed,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: true,
  remindEveryDays: every,
  lastRemindedAt: last,
);

void main() {
  final now = DateTime(2026, 10, 22, 12);

  group('reminderDue', () {
    test('due once the period has passed, or when never sent', () {
      expect(reminderDue(ledger(every: 7), now), isTrue);
      expect(
        reminderDue(
          ledger(every: 7, last: now.subtract(const Duration(days: 7))),
          now,
        ),
        isTrue,
      );
      expect(
        reminderDue(
          ledger(every: 7, last: now.subtract(const Duration(days: 6))),
          now,
        ),
        isFalse,
      );
    });

    test('not due when off, when nothing is owed, or for the counterparty', () {
      expect(reminderDue(ledger(), now), isFalse);
      expect(reminderDue(ledger(every: 7, confirmed: 0), now), isFalse);
      expect(reminderDue(ledger(every: 7, confirmed: -100), now), isFalse);
      expect(reminderDue(ledger(every: 7, owner: false), now), isFalse);
    });
  });

  test('reminderMessage names the shop, the amount and the link', () {
    expect(
      reminderMessage(ledger(shop: 'بقالة النور'), 'https://x/#t'),
      'السلام عليكم سعد،\n'
      'تذكير بالرصيد المتفق عليه مع بقالة النور: 45.50 ر.س عليك.\n'
      'التفاصيل، وتأكيد القيود أو الاعتراض عليها:\n'
      'https://x/#t',
    );
    expect(
      reminderMessage(ledger(), 'u'),
      startsWith('السلام عليكم سعد،\nتذكير بالرصيد المتفق عليه: 45.50'),
    );
  });

  test('buildSummaries reads the reminder columns for the owner only', () {
    Map<String, dynamic> row(String owner) => {
      'id': 'L1',
      'owner_id': owner,
      'counterparty_id': 'cp',
      'counterparty_name': 'سعد',
      'currency': 'SAR',
      'remind_every_days': 7,
      'last_reminded_at': '2026-10-20T09:00:00+00:00',
      'business': null,
      'owner': {'full_name': 'أحمد'},
    };
    final mine = buildSummaries(
      ledgerRows: [row('me')],
      balanceRows: const [],
      myId: 'me',
    ).single;
    expect(mine.remindEveryDays, 7);
    expect(mine.lastRemindedAt, DateTime.utc(2026, 10, 20, 9));
    final theirs = buildSummaries(
      ledgerRows: [row('owner')],
      balanceRows: const [],
      myId: 'cp',
    ).single;
    expect(theirs.remindEveryDays, isNull);
    expect(theirs.lastRemindedAt, isNull);
  });

  group('on the ledger screen', () {
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

    testWidgets('the owner sets a period, then sends the due reminder', (
      tester,
    ) async {
      ledgers.ledgers = [ledger()];
      await openLedger(tester);
      expect(find.byKey(const Key('send_reminder_button')), findsNothing);

      await tap(tester, 'reminder_button');
      await tap(tester, 'remind_7');
      expect(ledgers.ledgers.single.remindEveryDays, 7);
      await tester.tapAt(const Offset(180, 40)); // close the sheet
      await tester.pumpAndSettle();

      // Never sent and owed: due now.
      await tap(tester, 'send_reminder_button');
      expect(ledgers.shareLinks, {'L1': 'tok1'});
      expect(ledgers.reminded, {'L1': 1});
      expect(clipboard, [
        reminderMessage(ledgers.ledgers.single, DainConfig.shareUrl('tok1')),
      ]);
      expect(
        find.text('نُسخت رسالة التذكير. أرسلها له عبر واتساب أو رسالة.'),
        findsOneWidget,
      );
      // Sent just now: no longer due.
      expect(find.byKey(const Key('send_reminder_button')), findsNothing);

      await tap(tester, 'reminder_button');
      expect(find.byKey(const Key('last_reminder_text')), findsOneWidget);
      await tap(tester, 'remind_off');
      expect(ledgers.ledgers.single.remindEveryDays, isNull);
    });

    testWidgets('the list marks a ledger whose reminder is due', (
      tester,
    ) async {
      ledgers.ledgers = [ledger(every: 3)];
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = SessionController(auth: auth, profiles: profiles);
      await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
      await c.start();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('ledger_L1')),
          matching: find.textContaining('تذكير مستحق'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the counterparty has no reminder button', (tester) async {
      ledgers.ledgers = [ledger(owner: false, every: 3)];
      await openLedger(tester);
      expect(find.byKey(const Key('reminder_button')), findsNothing);
      expect(find.byKey(const Key('send_reminder_button')), findsNothing);
    });
  });
}
