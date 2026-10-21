import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/phone_number.dart';
import '../data/auth_repository.dart';
import '../data/profile_repository.dart';

enum SessionStage {
  /// Restoring a saved session.
  starting,
  enterPhone,
  enterCode,

  /// Signed in, no row in `profiles` yet.
  needsProfile,

  /// Signed in with a profile, but loading it or linking ledgers failed.
  failed,

  /// Profile exists and `link_my_ledgers()` has run for this session.
  ready,
}

/// The whole sign-in flow: phone -> OTP -> profile -> link_my_ledgers.
///
/// `link_my_ledgers()` runs on every entry to [SessionStage.ready], not only
/// after the first sign-in, so ledgers someone records against this phone
/// later are attached on the next launch. It is idempotent.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthRepository auth,
    required ProfileRepository profiles,
  }) : _auth = auth,
       _profiles = profiles;

  final AuthRepository _auth;
  final ProfileRepository _profiles;

  SessionStage _stage = SessionStage.starting;
  SessionStage get stage => _stage;

  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  String? _phone;

  /// The normalized number the code was sent to.
  String? get phone => _phone;

  Profile? _profile;
  Profile? get profile => _profile;

  int? _linkedCount;

  /// Ledgers attached by the last `link_my_ledgers()` call.
  int? get linkedCount => _linkedCount;

  Future<void> start() async {
    if (_auth.currentUserId == null) {
      _set(SessionStage.enterPhone);
      return;
    }
    await _afterSignIn();
  }

  Future<void> requestCode(String input) async {
    final phone = normalizePhone(input);
    if (phone == null) {
      _fail(invalidPhoneMessage);
      return;
    }
    await _run(() async {
      await _auth.sendOtp(phone);
      _phone = phone;
      _stage = SessionStage.enterCode;
    });
  }

  Future<void> verifyCode(String input) async {
    final phone = _phone;
    final code = asciiDigits(input);
    if (phone == null) {
      _set(SessionStage.enterPhone);
      return;
    }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      _fail('الرمز من 6 أرقام.');
      return;
    }
    final ok = await _run(() => _auth.verifyOtp(phone, code));
    if (ok) await _afterSignIn();
  }

  void changeNumber() {
    _phone = null;
    _set(SessionStage.enterPhone);
  }

  Future<void> createProfile(String input) async {
    final name = input.trim();
    if (name.isEmpty || name.runes.length > 80) {
      _fail('اكتب اسمك (حتى 80 حرفاً).');
      return;
    }
    final ok = await _run(() async {
      _profile = await _profiles.create(name);
    });
    if (ok) await _link();
  }

  Future<void> retry() => _afterSignIn();

  Future<void> signOut() async {
    await _run(_auth.signOut);
    _phone = null;
    _profile = null;
    _linkedCount = null;
    _set(SessionStage.enterPhone);
  }

  Future<void> _afterSignIn() async {
    Profile? profile;
    final ok = await _run(() async {
      profile = await _profiles.fetchMine();
    }, onError: SessionStage.failed);
    if (!ok) return;
    _profile = profile;
    if (profile == null) {
      _set(SessionStage.needsProfile);
      return;
    }
    await _link();
  }

  Future<void> _link() async {
    await _run(() async {
      _linkedCount = await _profiles.linkMyLedgers();
      _stage = SessionStage.ready;
    }, onError: SessionStage.failed);
  }

  /// Runs [action] with [busy] set. On failure keeps the current stage (or
  /// moves to [onError]) and exposes an Arabic [error]. Returns success.
  Future<bool> _run(
    Future<void> Function() action, {
    SessionStage? onError,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _error = arabicMessageFor(e);
      if (onError != null) _stage = onError;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _set(SessionStage stage) {
    _stage = stage;
    _error = null;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    notifyListeners();
  }
}
