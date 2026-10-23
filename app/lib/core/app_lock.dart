import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device check behind the app lock: fingerprint, face, or the device
/// PIN or pattern when there is no biometric.
abstract interface class Biometrics {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class LocalBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate(String reason) => _auth.authenticate(
    localizedReason: reason,
    persistAcrossBackgrounding: true,
  );
}

/// Where this device keeps whether the lock is on.
abstract interface class LockStore {
  Future<bool> read();
  Future<void> write(bool enabled);
}

class PrefsLockStore implements LockStore {
  static const _key = 'dain.app_lock';

  @override
  Future<bool> read() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> write(bool enabled) async =>
      (await SharedPreferences.getInstance()).setBool(_key, enabled);
}

/// The app lock: when on, the app opens locked, and locks again after it
/// spent [grace] or more in the background. The Supabase session stays as it
/// is; the lock only hides the app until the device check passes.
class AppLockController extends ChangeNotifier {
  AppLockController({
    required Biometrics biometrics,
    required LockStore store,
    this.grace = const Duration(seconds: 30),
    DateTime Function() now = DateTime.now,
  }) : _biometrics = biometrics,
       _store = store,
       _now = now;

  final Biometrics _biometrics;
  final LockStore _store;
  final Duration grace;
  final DateTime Function() _now;

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _locked = false;
  bool get locked => _locked;

  bool _busy = false;
  bool get busy => _busy;

  DateTime? _hiddenAt;

  /// Reads the setting; a device with the lock on opens locked.
  Future<void> load() async {
    try {
      _enabled = await _store.read();
    } catch (_) {
      _enabled = false;
    }
    _locked = _enabled;
    notifyListeners();
  }

  Future<bool> unlock() async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      if (await _biometrics.authenticate('افتح دائن')) _locked = false;
    } catch (_) {
      // Cancelled or not possible right now: stay locked, try again.
    } finally {
      _busy = false;
      notifyListeners();
    }
    return !_locked;
  }

  /// Turns the lock on (after one successful check) or off. Returns why it
  /// could not, or null.
  Future<String?> setEnabled(bool on) async {
    if (_busy) return null;
    if (!on) {
      await _store.write(false);
      _enabled = false;
      _locked = false;
      notifyListeners();
      return null;
    }
    _busy = true;
    notifyListeners();
    try {
      if (!await _biometrics.isAvailable()) {
        return 'هذا الجوال بلا بصمة ولا رمز قفل. فعّل قفل الشاشة في إعداداته أولاً.';
      }
      if (!await _biometrics.authenticate('فعّل قفل دائن')) {
        return 'لم يتم التحقق، فبقي القفل مطفأً.';
      }
      await _store.write(true);
      _enabled = true;
      return null;
    } catch (_) {
      return 'لم يتم التحقق، فبقي القفل مطفأً.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// The app went to the background.
  void hidden() => _hiddenAt ??= _now();

  /// The app came back: lock if it was away long enough.
  void shown() {
    final at = _hiddenAt;
    _hiddenAt = null;
    if (_enabled && at != null && _now().difference(at) >= grace) {
      _locked = true;
      notifyListeners();
    }
  }
}
