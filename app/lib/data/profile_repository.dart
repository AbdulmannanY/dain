import 'package:supabase_flutter/supabase_flutter.dart';

class Profile {
  const Profile({required this.id, required this.fullName});

  final String id;
  final String fullName;
}

/// The signed-in person's row in `public.profiles` and the RPC that attaches
/// ledgers recorded against their verified phone.
abstract interface class ProfileRepository {
  /// Null when the signed-in user has not created a profile yet.
  Future<Profile?> fetchMine();
  Future<Profile> create(String fullName);

  /// Calls `public.link_my_ledgers()`; returns how many ledgers it attached.
  /// The function requires an existing profile.
  Future<int> linkMyLedgers();
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthException('not signed in', code: 'not_signed_in');
    }
    return id;
  }

  @override
  Future<Profile?> fetchMine() async {
    final row = await _client
        .from('profiles')
        .select('id, full_name')
        .eq('id', _uid)
        .maybeSingle();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<Profile> create(String fullName) async {
    try {
      final row = await _client
          .from('profiles')
          .insert({'id': _uid, 'full_name': fullName})
          .select('id, full_name')
          .single();
      return _fromRow(row);
    } on PostgrestException catch (e) {
      // A retried submit after the first insert landed: keep the stored row.
      final existing = e.code == '23505' ? await fetchMine() : null;
      if (existing == null) rethrow;
      return existing;
    }
  }

  @override
  Future<int> linkMyLedgers() async {
    final n = await _client.rpc<dynamic>('link_my_ledgers');
    return (n as num).toInt();
  }

  static Profile _fromRow(Map<String, dynamic> row) =>
      Profile(id: row['id'] as String, fullName: row['full_name'] as String);
}
