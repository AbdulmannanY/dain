import 'package:supabase_flutter/supabase_flutter.dart';

/// One ledger as the signed-in person sees it. The database keeps balances
/// relative to the ledger OWNER; every amount here is already turned to the
/// viewer's side: positive = the other party owes me ("لك"),
/// negative = I owe them ("عليك").
class LedgerSummary {
  const LedgerSummary({
    required this.id,
    required this.iAmOwner,
    required this.title,
    required this.subtitle,
    required this.currency,
    required this.myConfirmedMinor,
    required this.myOpenMinor,
    required this.pendingCount,
    required this.disputedCount,
    required this.otherPartyJoined,
  });

  final String id;
  final bool iAmOwner;

  /// The other party: the counterparty's name for the owner; the shop's (or
  /// the owner's) name for the counterparty.
  final String title;

  /// The shop's name under the owner's view of a shop ledger, the owner's name
  /// under the counterparty's view of one; null for personal ledgers.
  final String? subtitle;
  final String currency;

  /// Entries both sides agreed on.
  final int myConfirmedMinor;

  /// Confirmed plus still-pending entries.
  final int myOpenMinor;
  final int pendingCount;
  final int disputedCount;

  /// False while the counterparty has not signed in with that phone yet
  /// (owner's view only; always true for the counterparty).
  final bool otherPartyJoined;
}

/// Turns PostgREST rows into summaries for [myId]. A ledger missing from
/// [balanceRows] (created between the two reads) counts as all zeros.
/// Sorted by the size of the agreed balance, largest first, then by title.
List<LedgerSummary> buildSummaries({
  required List<Map<String, dynamic>> ledgerRows,
  required List<Map<String, dynamic>> balanceRows,
  required String myId,
}) {
  final balances = {for (final b in balanceRows) b['ledger_id'] as String: b};
  final out = <LedgerSummary>[];
  for (final l in ledgerRows) {
    final id = l['id'] as String;
    final iAmOwner = l['owner_id'] == myId;
    final sign = iAmOwner ? 1 : -1;
    final shop = (l['business'] as Map<String, dynamic>?)?['name'] as String?;
    final ownerName =
        (l['owner'] as Map<String, dynamic>?)?['full_name'] as String? ?? '—';
    final b = balances[id];
    int n(String k) => (b?[k] as num?)?.toInt() ?? 0;

    out.add(
      LedgerSummary(
        id: id,
        iAmOwner: iAmOwner,
        title: iAmOwner
            ? l['counterparty_name'] as String
            : (shop ?? ownerName),
        subtitle: iAmOwner ? shop : (shop == null ? null : ownerName),
        currency: l['currency'] as String,
        myConfirmedMinor: sign * n('confirmed_balance_minor'),
        myOpenMinor: sign * n('open_balance_minor'),
        pendingCount: n('pending_count'),
        disputedCount: n('disputed_count'),
        otherPartyJoined: !iAmOwner || l['counterparty_id'] != null,
      ),
    );
  }
  out.sort((a, b) {
    final bySize = b.myConfirmedMinor.abs().compareTo(a.myConfirmedMinor.abs());
    return bySize != 0 ? bySize : a.title.compareTo(b.title);
  });
  return out;
}

/// Totals of agreed balances per currency, from the viewer's side.
class BalanceTotal {
  const BalanceTotal(this.currency, this.owedToMeMinor, this.iOweMinor);

  final String currency;
  final int owedToMeMinor;
  final int iOweMinor;
}

List<BalanceTotal> totalsByCurrency(List<LedgerSummary> ledgers) {
  final toMe = <String, int>{};
  final iOwe = <String, int>{};
  for (final l in ledgers) {
    final v = l.myConfirmedMinor;
    if (v > 0) toMe.update(l.currency, (x) => x + v, ifAbsent: () => v);
    if (v < 0) iOwe.update(l.currency, (x) => x - v, ifAbsent: () => -v);
  }
  final currencies = {...toMe.keys, ...iOwe.keys}.toList()..sort();
  return [
    for (final c in currencies) BalanceTotal(c, toMe[c] ?? 0, iOwe[c] ?? 0),
  ];
}

/// A shop the signed-in person owns.
class Business {
  const Business({required this.id, required this.name});

  final String id;
  final String name;
}

abstract interface class LedgerRepository {
  /// Every ledger I own or am the linked counterparty of (RLS decides).
  Future<List<LedgerSummary>> fetchMine();

  /// My verified phone as E.164 digits without '+', the form
  /// `link_my_ledgers()` matches; null when unknown.
  String? get myPhone;

  /// Shops I own, by name.
  Future<List<Business>> fetchMyBusinesses();

  Future<Business> createBusiness(String name);

  /// Opens a ledger I own for [phone] (normalized), under [businessId] or
  /// personal when null. Returns the new ledger's id. A second ledger for the
  /// same phone under the same shop (or personally) fails with `23505`.
  Future<String> openLedger({
    required String counterpartyName,
    required String phone,
    String? businessId,
  });
}

class SupabaseLedgerRepository implements LedgerRepository {
  SupabaseLedgerRepository(this._client);

  final SupabaseClient _client;

  String get _myId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthException('not signed in', code: 'not_signed_in');
    }
    return id;
  }

  @override
  Future<List<LedgerSummary>> fetchMine() async {
    final myId = _myId;
    // ledgers has two FKs to profiles, so the owner embed names its FK.
    final ledgers = await _client
        .from('ledgers')
        .select(
          'id, owner_id, counterparty_id, counterparty_name, currency, '
          'business:businesses(name), '
          'owner:profiles!ledgers_owner_id_fkey(full_name)',
        );
    // ledger_balances is a security_invoker view: same RLS as ledgers.
    final balances = await _client
        .from('ledger_balances')
        .select(
          'ledger_id, confirmed_balance_minor, open_balance_minor, '
          'pending_count, disputed_count',
        );
    return buildSummaries(
      ledgerRows: ledgers,
      balanceRows: balances,
      myId: myId,
    );
  }

  @override
  String? get myPhone {
    final phone = _client.auth.currentUser?.phone ?? '';
    if (phone.isEmpty) return null;
    return phone.startsWith('+') ? phone.substring(1) : phone;
  }

  @override
  Future<List<Business>> fetchMyBusinesses() async {
    // RLS also shows the shops of ledgers I am the counterparty of.
    final rows = await _client
        .from('businesses')
        .select('id, name')
        .eq('owner_id', _myId)
        .order('name');
    return [for (final r in rows) _business(r)];
  }

  @override
  Future<Business> createBusiness(String name) async {
    final row = await _client
        .from('businesses')
        .insert({'name': name})
        .select('id, name')
        .single();
    return _business(row);
  }

  @override
  Future<String> openLedger({
    required String counterpartyName,
    required String phone,
    String? businessId,
  }) async {
    final row = await _client
        .from('ledgers')
        .insert({
          'counterparty_name': counterpartyName,
          'counterparty_phone': phone,
          'business_id': ?businessId,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Business _business(Map<String, dynamic> row) =>
      Business(id: row['id'] as String, name: row['name'] as String);
}
