import 'dart:async';

import 'package:dain/boot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// DainBoot draws before initialization finishes and shows a failure
/// instead of leaving the launch screen blank.
void main() {
  Future<void> pumpBoot(WidgetTester tester, Widget boot) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(boot);
  }

  testWidgets('something is on screen while init runs, then the app', (
    tester,
  ) async {
    final done = Completer<Widget>();
    await pumpBoot(tester, DainBoot(init: () => done.future));
    await tester.pump();
    expect(find.byKey(const Key('boot_starting')), findsOneWidget);

    done.complete(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Text('app', key: Key('the_app')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('the_app')), findsOneWidget);
  });

  testWidgets('a failure is shown with its detail, and retry runs again', (
    tester,
  ) async {
    var calls = 0;
    Future<Widget> init() async {
      calls++;
      if (calls == 1) throw StateError('no storage');
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Text('app', key: Key('the_app')),
      );
    }

    await pumpBoot(tester, DainBoot(init: init));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boot_failed')), findsOneWidget);
    expect(find.textContaining('no storage'), findsOneWidget);

    await tester.tap(find.byKey(const Key('boot_retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const Key('the_app')), findsOneWidget);
  });

  testWidgets('a hang ends in a timeout message', (tester) async {
    await pumpBoot(
      tester,
      DainBoot(
        init: () => Completer<Widget>().future,
        timeout: const Duration(seconds: 2),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('انتهت المهلة أثناء التهيئة.'), findsOneWidget);
    expect(find.byKey(const Key('boot_retry')), findsOneWidget);
  });
}
