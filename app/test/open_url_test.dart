import 'package:dain/app.dart';
import 'package:dain/core/config.dart';
import 'package:dain/core/open_url.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

LedgerSummary ledger({String? phone = '966500000002'}) => LedgerSummary(
  id: 'L1',
  iAmOwner: true,
  title: 'سعد',
  subtitle: null,
  currency: 'SAR',
  myConfirmedMinor: 4550,
  myOpenMinor: 4550,
  pendingCount: 0,
  disputedCount: 0,
  otherPartyJoined: true,
  remindEveryDays: 7,
  counterpartyPhone: phone,
);

void main() {
  test('whatsappUrl: the stored number, the text percent-encoded', () {
    final url = whatsappUrl('966500000002', 'سعد، عليك\n45 ر.س #x');
    expect(url.host, 'wa.me');
    expect(url.path, '/966500000002');
    expect(url.queryParameters['text'], 'سعد، عليك\n45 ر.س #x');
    expect(url.toString(), isNot(contains('+')));
    expect(url.toString(), contains('%0A'));
  });

  group('opening links', () {
    late FakeLedgers ledgers;
    late List<Uri> opened;
    late bool canOpen;
    late List<String> clipboard;
    late SessionController session;

    setUp(() {
      opened = [];
      canOpen = true;
      clipboard = [];
      openUrl = (url) async {
        opened.add(url);
        return canOpen;
      };
    });
    tearDown(() => openUrl = (_) async => false);

    Future<void> launch(WidgetTester tester, LedgerSummary l) async {
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
      final auth = FakeAuth(signedInAs: '966500000001');
      final profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
      ledgers = FakeLedgers([l]);
      session = SessionController(auth: auth, profiles: profiles);
      await tester.pumpWidget(DainApp(controller: session, ledgers: ledgers));
      await session.start();
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('a due reminder opens WhatsApp with the message, also copied', (
      tester,
    ) async {
      await launch(tester, ledger());
      await tap(tester, 'ledger_L1');
      await tap(tester, 'send_reminder_button');

      final message = reminderMessage(
        ledgers.ledgers.single,
        DainConfig.shareUrl('tok1'),
      );
      expect(clipboard, [message]);
      expect(opened, [whatsappUrl('966500000002', message)]);
      expect(ledgers.reminded, {'L1': 1});
      expect(
        find.text('فُتح واتساب برسالة التذكير، ونُسخت أيضاً.'),
        findsOneWidget,
      );
    });

    testWidgets('no WhatsApp: the reminder stays copied and says so', (
      tester,
    ) async {
      canOpen = false;
      await launch(tester, ledger());
      await tap(tester, 'ledger_L1');
      await tap(tester, 'send_reminder_button');
      expect(opened, hasLength(1));
      expect(clipboard, hasLength(1));
      expect(
        find.text('نُسخت رسالة التذكير. أرسلها له عبر واتساب أو رسالة.'),
        findsOneWidget,
      );
    });

    testWidgets('a new share link can go out on WhatsApp', (tester) async {
      await launch(tester, ledger());
      await tap(tester, 'ledger_L1');
      await tap(tester, 'share_link_button');
      expect(find.byKey(const Key('share_whatsapp_button')), findsNothing);
      await tap(tester, 'create_link_button');
      await tap(tester, 'share_whatsapp_button');
      final url = DainConfig.shareUrl('tok1');
      expect(opened, [
        whatsappUrl(
          '966500000002',
          shareLinkMessage(ledgers.ledgers.single, url),
        ),
      ]);
      expect(clipboard, [url]);
    });

    testWidgets('the privacy policy opens from my account', (tester) async {
      await launch(tester, ledger());
      await tap(tester, 'account_button');
      await tap(tester, 'privacy_link');
      expect(opened, [Uri.parse(DainConfig.privacyUrl)]);
      expect(
        DainConfig.privacyUrl,
        'https://abdulmannany.github.io/dain/privacy.html',
      );

      canOpen = false;
      await tap(tester, 'privacy_link');
      expect(find.textContaining('تعذّر فتح الصفحة'), findsOneWidget);
    });
  });
}
