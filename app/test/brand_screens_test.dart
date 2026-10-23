import 'package:dain/app.dart';
import 'package:dain/session/session_controller.dart';
import 'package:dain/ui/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The entry screens' new look through the real DainApp at 360 px: the
/// brand, the step bar, and the code boxes that mirror the hidden field.
void main() {
  late FakeAuth auth;
  late SessionController c;

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = SessionController(auth: auth, profiles: FakeProfiles(auth));
    await tester.pumpWidget(DainApp(controller: c, ledgers: FakeLedgers()));
    await c.start();
    await tester.pumpAndSettle();
  }

  Text box(WidgetTester tester, int i) => tester.widget<Text>(
    find.descendant(
      of: find.byKey(Key('code_box_$i')),
      matching: find.byType(Text),
    ),
  );

  setUp(() => auth = FakeAuth(codes: {'966501234567': '123456'}));

  testWidgets('phone: the brand with its tagline, step 1 of 3', (tester) async {
    await launch(tester);
    expect(find.byKey(const Key('brand_mark')), findsOneWidget);
    expect(find.text(Brand.tagline), findsOneWidget);
    expect(find.byKey(const Key('step_bar_0')), findsOneWidget);
  });

  testWidgets('code: six boxes show what is typed; step 2, no tagline', (
    tester,
  ) async {
    await launch(tester);
    await tester.enterText(find.byKey(const Key('phone_field')), '0501234567');
    await tester.tap(find.byKey(const Key('send_code_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('step_bar_1')), findsOneWidget);
    expect(find.text(Brand.tagline), findsNothing);
    expect(find.byKey(const Key('code_box_5')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code_field')), '12');
    await tester.pump();
    expect(box(tester, 0).data, '1');
    expect(box(tester, 1).data, '2');
    expect(box(tester, 2).data, '');

    await tester.enterText(find.byKey(const Key('code_field')), '123456');
    await tester.tap(find.byKey(const Key('verify_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('step_bar_2')), findsOneWidget);
    expect(find.byKey(const Key('name_field')), findsOneWidget);
  });

  testWidgets('the theme is Dain green in light and dark', (tester) async {
    expect(DainApp.theme(Brightness.light).colorScheme.primary, Brand.green);
    expect(DainApp.theme(Brightness.dark).colorScheme.secondary, Brand.gold);
  });
}
