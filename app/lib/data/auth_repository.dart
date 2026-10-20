import 'package:supabase_flutter/supabase_flutter.dart';

/// Phone OTP sign-in. [phone] is always the normalized E.164 digits.
abstract interface class AuthRepository {
  String? get currentUserId;
  Future<void> sendOtp(String phone);
  Future<void> verifyOtp(String phone, String code);
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> sendOtp(String phone) =>
      _client.auth.signInWithOtp(phone: '+$phone');

  @override
  Future<void> verifyOtp(String phone, String code) async {
    final res = await _client.auth.verifyOTP(
      phone: '+$phone',
      token: code,
      type: OtpType.sms,
    );
    if (res.session == null) {
      throw const AuthException('no session', code: 'no_session');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
