import 'package:dain/data/auth_repository.dart';
import 'package:dain/data/ledger_repository.dart';
import 'package:dain/data/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-ins that behave like the Supabase side: OTP codes per
/// phone, one profile per user, link_my_ledgers() refusing without a profile.
class FakeAuth implements AuthRepository {
  FakeAuth({this.codes = const {}, this.signedInAs});

  final Map<String, String> codes;
  String? signedInAs;
  final sent = <String>[];

  @override
  String? get currentUserId => signedInAs == null ? null : 'user-$signedInAs';

  @override
  Future<void> sendOtp(String phone) async {
    if (!codes.containsKey(phone)) {
      throw const AuthException('send failed', code: 'sms_send_failed');
    }
    sent.add(phone);
  }

  @override
  Future<void> verifyOtp(String phone, String code) async {
    if (!sent.contains(phone) || codes[phone] != code) {
      throw const AuthException('invalid', code: 'otp_expired');
    }
    signedInAs = phone;
  }

  @override
  Future<void> signOut() async => signedInAs = null;
}

class FakeProfiles implements ProfileRepository {
  FakeProfiles(this.auth, {Map<String, String>? names, this.pendingLedgers = 0})
    : names = names ?? {};

  final FakeAuth auth;

  /// user id -> full name
  final Map<String, String> names;

  /// Ledgers waiting for this phone; the first link attaches them all.
  int pendingLedgers;
  int linkCalls = 0;
  bool failLink = false;

  String get _uid => auth.currentUserId!;

  @override
  Future<Profile?> fetchMine() async {
    final name = names[_uid];
    return name == null ? null : Profile(id: _uid, fullName: name);
  }

  @override
  Future<Profile> create(String fullName) async {
    names.putIfAbsent(_uid, () => fullName);
    return Profile(id: _uid, fullName: names[_uid]!);
  }

  @override
  Future<int> linkMyLedgers() async {
    linkCalls++;
    if (failLink) {
      throw const PostgrestException(message: 'boom', code: '500');
    }
    if (!names.containsKey(_uid)) {
      throw const PostgrestException(
        message: 'profile required',
        code: '42501',
      );
    }
    final n = pendingLedgers;
    pendingLedgers = 0;
    return n;
  }
}

/// Returns [ledgers] (or throws [failWith]) on each fetch.
class FakeLedgers implements LedgerRepository {
  FakeLedgers([this.ledgers = const []]);

  List<LedgerSummary> ledgers;
  Object? failWith;
  int fetches = 0;

  @override
  Future<List<LedgerSummary>> fetchMine() async {
    fetches++;
    final error = failWith;
    if (error != null) throw error;
    return ledgers;
  }
}
