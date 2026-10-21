import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// "My shops" from the list's app bar, through the real DainApp, on a
/// phone-sized screen.
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late FakeLedgers ledgers;

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers()
      ..businesses = [
        const Business(id: 's1', name: 'بقالة النور'),
        const Business(id: 's2', name: 'محل الوفاء'),
      ]
      ..shopsWithLedgers.add('s1');
  });

  Future<void> openShops(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shops_button')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('lists my shops and renames one, trimmed', (tester) async {
    await openShops(tester);
    expect(find.text('بقالة النور'), findsOneWidget);
    expect(find.text('محل الوفاء'), findsOneWidget);

    await tap(tester, 'shop_s2');
    await tester.enterText(find.byKey(const Key('shop_name_field')), '  ');
    await tap(tester, 'save_shop_button');
    expect(find.text('اكتب اسم المحل (حتى 80 حرفاً).'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('shop_name_field')),
      ' محل الوفاء الجديد ',
    );
    await tap(tester, 'save_shop_button');
    expect(
      ledgers.businesses.map((b) => b.name),
      contains('محل الوفاء الجديد'),
    );
    expect(find.text('حُفظ اسم المحل.'), findsOneWidget);
    expect(find.text('محل الوفاء الجديد'), findsOneWidget);
  });

  testWidgets('an empty shop is deleted after a second tap', (tester) async {
    await openShops(tester);
    await tap(tester, 'shop_s2');
    await tap(tester, 'delete_shop_button');
    expect(ledgers.businesses, hasLength(2));
    await tap(tester, 'confirm_delete_shop_button');

    expect(ledgers.businesses.map((b) => b.id), ['s1']);
    expect(find.text('حُذف المحل.'), findsOneWidget);
    expect(find.byKey(const Key('shop_s2')), findsNothing);
  });

  testWidgets('a shop with ledgers is not deleted', (tester) async {
    await openShops(tester);
    await tap(tester, 'shop_s1');
    await tap(tester, 'delete_shop_button');
    await tap(tester, 'confirm_delete_shop_button');

    expect(ledgers.businesses, hasLength(2));
    expect(
      find.text(
        'لا يُحذف محل فيه دفاتر. الدفتر سجل مشترك مع الطرف الآخر ولا يُحذف.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no shops yet', (tester) async {
    ledgers.businesses = [];
    await openShops(tester);
    expect(find.byKey(const Key('shops_empty')), findsOneWidget);
  });
}
