import 'package:dain/app.dart';
import 'package:dain/core/phone_number.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Drives the real app widget (DainApp -> SessionGate -> screens ->
/// SessionController) with in-memory repositories.
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late SessionController controller;

  Future<void> launch(WidgetTester tester) async {
    controller = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(
      DainApp(controller: controller, ledgers: FakeLedgers()),
    );
    await controller.start();
    await tester.pumpAndSettle();
  }

  Future<void> enter(
    WidgetTester tester,
    String field,
    String text,
    String button,
  ) async {
    await tester.enterText(find.byKey(Key(field)), text);
    await tester.tap(find.byKey(Key(button)));
    await tester.pumpAndSettle();
  }

  setUp(() {
    auth = FakeAuth(
      codes: {'966500000001': '123456', '966500000002': '123456'},
    );
    profiles = FakeProfiles(auth);
  });

  testWidgets('new user: phone -> code -> profile -> ledgers linked', (
    tester,
  ) async {
    profiles.pendingLedgers = 2;
    await launch(tester);
    expect(find.byKey(const Key('phone_field')), findsOneWidget);

    await enter(tester, 'phone_field', '0500000002', 'send_code_button');
    expect(auth.sent, ['966500000002']);
    expect(find.byKey(const Key('code_field')), findsOneWidget);

    await enter(tester, 'code_field', '١٢٣٤٥٦', 'verify_button');
    expect(controller.stage, SessionStage.needsProfile);
    expect(
      profiles.linkCalls,
      0,
      reason: 'link_my_ledgers needs a profile first',
    );

    await enter(tester, 'name_field', '  بدر  ', 'save_profile_button');
    expect(profiles.names['user-966500000002'], 'بدر');
    expect(profiles.linkCalls, 1);
    expect(controller.stage, SessionStage.ready);
    expect(find.text('أهلاً، بدر'), findsOneWidget);
    expect(find.text('أُضيف إلى حسابك دفتران مسجّلان برقمك.'), findsOneWidget);
  });

  testWidgets('returning user with a saved session links again on launch', (
    tester,
  ) async {
    auth.signedInAs = '966500000001';
    profiles.names['user-966500000001'] = 'أحمد';
    profiles.pendingLedgers = 1;
    await launch(tester);

    expect(profiles.linkCalls, 1);
    expect(find.text('أهلاً، أحمد'), findsOneWidget);
    expect(find.text('أُضيف إلى حسابك دفتر واحد مسجّل برقمك.'), findsOneWidget);
  });

  testWidgets('existing profile signing in skips the name screen', (
    tester,
  ) async {
    profiles.names['user-966500000001'] = 'أحمد';
    await launch(tester);
    await enter(tester, 'phone_field', '+966 50 000 0001', 'send_code_button');
    await enter(tester, 'code_field', '123456', 'verify_button');

    expect(find.byKey(const Key('name_field')), findsNothing);
    expect(controller.stage, SessionStage.ready);
    expect(find.text('دفاتري'), findsOneWidget);
    expect(find.byKey(const Key('linked_banner')), findsNothing);
  });

  testWidgets('a Yemeni number is sent with 967, not as another country', (
    tester,
  ) async {
    auth = FakeAuth(codes: {'967774040697': '123456'});
    profiles = FakeProfiles(auth, names: {'user-967774040697': 'عبدالرحمن'});
    await launch(tester);
    await enter(tester, 'phone_field', '774040697', 'send_code_button');
    expect(auth.sent, ['967774040697']);
    await enter(tester, 'code_field', '123456', 'verify_button');
    expect(controller.stage, SessionStage.ready);
  });

  testWidgets('invalid phone never reaches the server', (tester) async {
    await launch(tester);
    await enter(tester, 'phone_field', '0112345678', 'send_code_button');

    expect(auth.sent, isEmpty);
    expect(find.text(invalidPhoneMessage), findsOneWidget);
    expect(controller.stage, SessionStage.enterPhone);
  });

  testWidgets('wrong code stays on the code screen with an Arabic error', (
    tester,
  ) async {
    await launch(tester);
    await enter(tester, 'phone_field', '0500000001', 'send_code_button');
    await enter(tester, 'code_field', '654321', 'verify_button');

    expect(controller.stage, SessionStage.enterCode);
    expect(find.text('الرمز غير صحيح أو انتهت صلاحيته.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('change_number_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phone_field')), findsOneWidget);
  });

  testWidgets('link failure shows retry, and retry completes', (tester) async {
    auth.signedInAs = '966500000001';
    profiles.names['user-966500000001'] = 'أحمد';
    profiles.failLink = true;
    await launch(tester);
    expect(controller.stage, SessionStage.failed);
    expect(find.byKey(const Key('retry_button')), findsOneWidget);

    profiles.failLink = false;
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();
    expect(controller.stage, SessionStage.ready);
    expect(profiles.linkCalls, 2);
  });

  testWidgets('sign out returns to the phone screen', (tester) async {
    auth.signedInAs = '966500000001';
    profiles.names['user-966500000001'] = 'أحمد';
    await launch(tester);
    await tester.tap(find.byKey(const Key('sign_out_button')));
    await tester.pumpAndSettle();

    expect(auth.currentUserId, isNull);
    expect(find.byKey(const Key('phone_field')), findsOneWidget);
  });
}
