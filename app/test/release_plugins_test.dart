import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release APKs are shrunk by R8, which renames or strips methods that a
/// plugin reaches through JNI by name. shared_preferences_android 2.5.x does
/// that, and dain-apk-15 failed at startup with NoSuchMethodError
/// SharedPreferencesApiRegistrar.getAll. Debug builds and widget tests never
/// see it, so this keeps the resolved packages honest instead.
void main() {
  final lock = File('pubspec.lock').readAsStringSync();

  String? locked(String name) => RegExp(
    '\\n  $name:\\n(?:.*\\n){0,6}?    version: "([^"]+)"',
  ).firstMatch(lock)?.group(1);

  test('shared_preferences_android stays below 2.5 (no JNI registrar)', () {
    final v = locked('shared_preferences_android');
    expect(v, isNotNull);
    final [major, minor, ...] = v!.split('.').map(int.parse).toList();
    expect(
      (major, minor),
      (2, 4),
      reason: 'shared_preferences_android $v: see pubspec.yaml before raising',
    );
  });

  test('no package resolves to the jni bridge', () {
    expect(locked('jni'), isNull, reason: 'jni is in pubspec.lock');
  });
}
