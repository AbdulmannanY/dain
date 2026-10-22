import 'package:dain/app.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

/// "My account" from the list's app bar, through the real DainApp, on a
/// phone-sized screen.
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late SessionController session;

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
  });

  Future<void> openAccount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(
      DainApp(controller: session, ledgers: FakeLedgers()),
    );
    await session.start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account_button')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('renames me, trimmed; an empty name is refused', (tester) async {
    await openAccount(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('account_name_field')))
          .controller!
          .text,
      'أحمد',
    );

    await tester.enterText(find.byKey(const Key('account_name_field')), '  ');
    await tap(tester, 'save_name_button');
    expect(find.text('اكتب اسمك (حتى 80 حرفاً).'), findsOneWidget);
    expect(profiles.names['user-966500000001'], 'أحمد');

    await tester.enterText(
      find.byKey(const Key('account_name_field')),
      ' أحمد سالم ',
    );
    await tap(tester, 'save_name_button');
    expect(profiles.names['user-966500000001'], 'أحمد سالم');
    expect(session.profile!.fullName, 'أحمد سالم');
    expect(find.byKey(const Key('name_saved_text')), findsOneWidget);
  });

  testWidgets('deleting takes a second tap, then lands on the phone screen', (
    tester,
  ) async {
    await openAccount(tester);
    await tap(tester, 'delete_account_button');
    expect(profiles.deleted, isEmpty);

    await tap(tester, 'confirm_delete_account_button');
    expect(profiles.deleted, ['user-966500000001']);
    expect(auth.signedInAs, isNull);
    expect(session.stage, SessionStage.enterPhone);
    expect(find.byKey(const Key('phone_field')), findsOneWidget);
    expect(find.byKey(const Key('account_name_field')), findsNothing);
  });

  testWidgets('a failed delete stays signed in and says so', (tester) async {
    await openAccount(tester);
    profiles.failNextWith = const PostgrestException(message: 'x', code: '500');
    await tap(tester, 'delete_account_button');
    await tap(tester, 'confirm_delete_account_button');
    expect(profiles.deleted, isEmpty);
    expect(auth.signedInAs, '966500000001');
    expect(find.text('تعذّر إتمام العملية. حاول مجدداً.'), findsOneWidget);
    expect(
      find.byKey(const Key('confirm_delete_account_button')),
      findsOneWidget,
    );
  });
}
