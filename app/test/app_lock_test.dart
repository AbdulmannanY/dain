import 'package:dain/app.dart';
import 'package:dain/core/app_lock.dart';
import 'package:dain/session/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class FakeBiometrics implements Biometrics {
  bool available = true;
  bool pass = true;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return pass;
  }
}

class FakeLockStore implements LockStore {
  FakeLockStore([this.value = false]);
  bool value;

  @override
  Future<bool> read() async => value;

  @override
  Future<void> write(bool enabled) async => value = enabled;
}

void main() {
  late FakeBiometrics bio;
  late FakeLockStore store;
  var now = DateTime(2026, 10, 23, 12);

  AppLockController lock() =>
      AppLockController(biometrics: bio, store: store, now: () => now);

  setUp(() {
    bio = FakeBiometrics();
    store = FakeLockStore();
    now = DateTime(2026, 10, 23, 12);
  });

  group('the lock', () {
    test(
      'a device with the lock on opens locked; the check opens it',
      () async {
        store.value = true;
        final l = lock();
        await l.load();
        expect(l.locked, isTrue);
        bio.pass = false;
        expect(await l.unlock(), isFalse);
        expect(l.locked, isTrue);
        bio.pass = true;
        expect(await l.unlock(), isTrue);
        expect(l.locked, isFalse);
      },
    );

    test('turning it on needs a device check that passes', () async {
      final l = lock();
      await l.load();
      bio.available = false;
      expect(await l.setEnabled(true), contains('بلا بصمة'));
      bio.available = true;
      bio.pass = false;
      expect(await l.setEnabled(true), contains('لم يتم التحقق'));
      expect(store.value, isFalse);
      bio.pass = true;
      expect(await l.setEnabled(true), isNull);
      expect(store.value, isTrue);
      expect(l.locked, isFalse); // turning it on does not lock me out now
      expect(await l.setEnabled(false), isNull);
      expect(store.value, isFalse);
    });

    test('it locks again only after 30 seconds in the background', () async {
      store.value = true;
      final l = lock();
      await l.load();
      await l.unlock();
      l.hidden();
      now = now.add(const Duration(seconds: 29));
      l.shown();
      expect(l.locked, isFalse);
      l.hidden();
      now = now.add(const Duration(seconds: 30));
      l.shown();
      expect(l.locked, isTrue);
    });
  });

  group('in the app', () {
    Future<void> launch(
      WidgetTester tester,
      AppLockController l, {
      String? signedInAs = '966500000001',
    }) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = FakeAuth(signedInAs: signedInAs);
      final c = SessionController(
        auth: auth,
        profiles: FakeProfiles(auth, names: {'user-966500000001': 'أحمد'}),
      );
      await tester.pumpWidget(
        DainApp(controller: c, ledgers: FakeLedgers(), appLock: l),
      );
      await c.start();
      await tester.pumpAndSettle();
    }

    testWidgets('signed in with the lock on: locked until the check passes', (
      tester,
    ) async {
      store.value = true;
      final l = lock();
      await l.load();
      await launch(tester, l);
      expect(find.byKey(const Key('lock_screen')), findsOneWidget);
      await tester.tap(find.byKey(const Key('unlock_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lock_screen')), findsNothing);
      expect(find.byKey(const Key('ledgers_list')), findsOneWidget);
    });

    testWidgets('signing in is never behind the lock', (tester) async {
      store.value = true;
      final l = lock();
      await l.load();
      await launch(tester, l, signedInAs: null);
      expect(find.byKey(const Key('phone_field')), findsOneWidget);
      expect(find.byKey(const Key('lock_screen')), findsNothing);
    });

    testWidgets('the account screen turns it on after a check', (tester) async {
      final l = lock();
      await l.load();
      await launch(tester, l);
      await tester.tap(find.byKey(const Key('account_button')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('app_lock_switch')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('app_lock_switch')));
      await tester.pumpAndSettle();
      expect(bio.asked, 1);
      expect(store.value, isTrue);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('app_lock_switch')))
            .value,
        isTrue,
      );
    });
  });
}
