import 'package:dain/app.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fakes.dart';

/// "New ledger" from the signed-in home, through the real DainApp, on a
/// phone-sized screen (overflow fails the test).
void main() {
  late FakeAuth auth;
  late FakeProfiles profiles;
  late FakeLedgers ledgers;

  setUp(() {
    auth = FakeAuth(signedInAs: '966500000001');
    profiles = FakeProfiles(auth, names: {'user-966500000001': 'أحمد'});
    ledgers = FakeLedgers()
      ..myPhone = '966500000001'
      ..businesses = [const Business(id: 'shop-a', name: 'بقالة النور')];
  });

  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_ledger_button')));
    await tester.pumpAndSettle();
    expect(find.text('دفتر جديد'), findsOneWidget);
  }

  Future<void> fill(
    WidgetTester tester, {
    String name = 'سعد',
    required String phone,
    String? owner,
    String? newShop,
  }) async {
    await tester.enterText(
      find.byKey(const Key('counterparty_name_field')),
      name,
    );
    await tester.enterText(
      find.byKey(const Key('counterparty_phone_field')),
      phone,
    );
    if (owner != null) {
      await tester.tap(find.byKey(Key(owner)));
      await tester.pumpAndSettle();
    }
    if (newShop != null) {
      await tester.enterText(find.byKey(const Key('new_shop_field')), newShop);
    }
    await tester.tap(find.byKey(const Key('open_ledger_button')));
    await tester.pumpAndSettle();
  }

  /// From the ledger's screen back to the list.
  Future<void> back(WidgetTester tester) async {
    // pageBack() looks for the English 'Back' tooltip; the app is Arabic.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  bool chipSelected(WidgetTester tester, String key) =>
      tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

  Finder inTile(String id, String text) => find.descendant(
    of: find.byKey(Key('ledger_$id')),
    matching: find.text(text),
  );

  testWidgets('opens a personal ledger, shows it, and the list has it', (
    tester,
  ) async {
    await openForm(tester);
    expect(chipSelected(tester, 'owner_personal'), isTrue);
    expect(find.byKey(const Key('new_shop_field')), findsNothing);

    await fill(tester, phone: '٠٥٠ ١٢٣ ٤٥٦٧');

    expect(ledgers.opened, [('', '966501234567')]);
    // The new ledger's own screen opens straight away.
    expect(find.byKey(const Key('entries_empty')), findsOneWidget);
    expect(find.byKey(const Key('not_joined_note')), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'سعد'), findsOneWidget);

    await back(tester);
    expect(find.byKey(const Key('ledgers_list')), findsOneWidget);
    expect(inTile('new-1', 'سعد'), findsOneWidget);
    expect(inTile('new-1', 'لم ينضم بعد'), findsOneWidget);
  });

  testWidgets('a shop ledger: the same phone twice in one shop is refused', (
    tester,
  ) async {
    await openForm(tester);
    await fill(tester, phone: '0501234567', owner: 'owner_shop_shop-a');
    expect(ledgers.opened, [('shop-a', '966501234567')]);
    await back(tester);
    expect(inTile('new-1', 'بقالة النور · لم ينضم بعد'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new_ledger_button')));
    await tester.pumpAndSettle();
    await fill(tester, phone: '+966501234567', owner: 'owner_shop_shop-a');
    expect(find.text('لهذا الرقم دفتر في هذا المحل بالفعل.'), findsOneWidget);
    expect(find.byKey(const Key('open_ledger_button')), findsOneWidget);

    // The same phone personally is a different ledger.
    await tester.tap(find.byKey(const Key('owner_personal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_ledger_button')));
    await tester.pumpAndSettle();
    expect(ledgers.opened, [('shop-a', '966501234567'), ('', '966501234567')]);
  });

  testWidgets('refuses my own number before creating anything', (tester) async {
    await openForm(tester);
    await fill(
      tester,
      phone: '+966 50 000 0001',
      owner: 'owner_new_shop',
      newShop: 'محل الوفاء',
    );
    expect(find.text('هذا رقمك أنت. أدخل رقم الطرف الآخر.'), findsOneWidget);
    expect(ledgers.opened, isEmpty);
    expect(ledgers.businesses, hasLength(1));
  });

  testWidgets('a new shop is created once when the ledger insert is retried', (
    tester,
  ) async {
    await openForm(tester);
    ledgers.failNextOpenWith = const PostgrestException(
      message: 'boom',
      code: '500',
    );
    await fill(
      tester,
      phone: '0509876543',
      owner: 'owner_new_shop',
      newShop: '  محل الوفاء ',
    );
    expect(find.text('تعذّر إتمام العملية. حاول مجدداً.'), findsOneWidget);
    expect(ledgers.businesses.map((b) => b.name), [
      'بقالة النور',
      'محل الوفاء',
    ]);
    // The created shop is now the selection; the new-shop field is gone.
    expect(chipSelected(tester, 'owner_shop_shop-2'), isTrue);
    expect(find.byKey(const Key('new_shop_field')), findsNothing);

    await tester.tap(find.byKey(const Key('open_ledger_button')));
    await tester.pumpAndSettle();
    expect(ledgers.businesses, hasLength(2));
    expect(ledgers.opened, [('shop-2', '966509876543')]);
    await back(tester);
    expect(inTile('new-1', 'محل الوفاء · لم ينضم بعد'), findsOneWidget);
  });

  testWidgets('checks the name, the phone and the new shop name', (
    tester,
  ) async {
    await openForm(tester);
    await fill(tester, name: '  ', phone: '0501234567');
    expect(find.text('اكتب اسم الطرف الآخر (حتى 80 حرفاً).'), findsOneWidget);

    await fill(tester, phone: '0112345678');
    expect(find.text('أدخل رقم جوال صحيحاً، مثل 05XXXXXXXX.'), findsOneWidget);

    await fill(tester, phone: '0501234567', owner: 'owner_new_shop');
    expect(find.text('اكتب اسم المحل (حتى 80 حرفاً).'), findsOneWidget);
    expect(ledgers.opened, isEmpty);
    expect(ledgers.businesses, hasLength(1));
  });

  testWidgets('a failed shop load offers a retry', (tester) async {
    ledgers.failWith = const PostgrestException(message: 'x', code: '500');
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SessionController(auth: auth, profiles: profiles);
    await tester.pumpWidget(DainApp(controller: c, ledgers: ledgers));
    await c.start();
    await tester.pumpAndSettle();
    // The home failed too; the button is there regardless.
    await tester.tap(find.byKey(const Key('new_ledger_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('retry_button')), findsOneWidget);

    ledgers.failWith = null;
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner_shop_shop-a')), findsOneWidget);
  });
}
