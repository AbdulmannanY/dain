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

  /// Set by [deleteAccount]: the user ids deleted.
  final deleted = <String>[];
  Object? failNextWith;

  @override
  Future<Profile> rename(String fullName) async {
    final error = failNextWith;
    if (error != null) {
      failNextWith = null;
      throw error;
    }
    names[_uid] = fullName;
    return Profile(id: _uid, fullName: fullName);
  }

  @override
  Future<void> deleteAccount() async {
    final error = failNextWith;
    if (error != null) {
      failNextWith = null;
      throw error;
    }
    deleted.add(_uid);
    names.remove(_uid);
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

/// Returns [ledgers] (or throws [failWith]) on each fetch. Opening a ledger
/// behaves like the database: one per (shop or personal, phone), `23505`
/// otherwise, and the new ledger shows up in the next fetch.
class FakeLedgers implements LedgerRepository {
  FakeLedgers([this.ledgers = const []]);

  List<LedgerSummary> ledgers;
  Object? failWith;
  int fetches = 0;

  @override
  String? myPhone;
  List<Business> businesses = [];

  /// Thrown once by the next [openLedger], after any shop was created.
  Object? failNextOpenWith;

  /// (business id or '', phone) of every ledger opened.
  final opened = <(String, String)>[];

  /// ledger id -> its entries from my side, newest first.
  final entries = <String, List<LedgerEntry>>{};

  /// Thrown once by the next [addEntry].
  Object? failNextAddWith;

  /// (ledger id, stored direction, amount, note, day) of every entry added.
  final added = <(String, String, int, String?, DateTime)>[];

  /// Thrown once by the next [respondEntry] or [voidEntry].
  Object? failNextActionWith;

  /// (entry id, 'confirmed' | 'disputed' | 'voided', note) of every action.
  final actions = <(String, String, String?)>[];

  /// ledger id -> its live link token; created ones get tok1, tok2...
  final shareLinks = <String, String>{};
  int _tokens = 0;

  @override
  Future<List<LedgerSummary>> fetchMine() async {
    fetches++;
    final error = failWith;
    if (error != null) throw error;
    return ledgers;
  }

  @override
  Future<LedgerSummary> fetchLedger(String id) async {
    final error = failWith;
    if (error != null) throw error;
    return ledgers.singleWhere((l) => l.id == id);
  }

  @override
  Future<List<LedgerEntry>> fetchEntries(LedgerSummary ledger) async {
    final error = failWith;
    if (error != null) throw error;
    return entries[ledger.id] ?? const [];
  }

  /// Like the database: a pending entry, counted in the open balance and the
  /// pending count of the ledger's summary.
  @override
  Future<void> addEntry(
    LedgerSummary ledger, {
    required bool iGave,
    required int amountMinor,
    String? note,
    required DateTime occurredOn,
  }) async {
    final error = failNextAddWith;
    if (error != null) {
      failNextAddWith = null;
      throw error;
    }
    final direction = entryDirection(iAmOwner: ledger.iAmOwner, iGave: iGave);
    added.add((ledger.id, direction, amountMinor, note, occurredOn));
    final delta = iGave ? amountMinor : -amountMinor;
    entries[ledger.id] = [
      LedgerEntry(
        id: 'e${added.length}',
        myDeltaMinor: delta,
        note: note,
        occurredOn: occurredOn,
        status: EntryStatus.pending,
        createdByMe: true,
        responseNote: null,
      ),
      ...?entries[ledger.id],
    ];
    ledgers = [
      for (final l in ledgers)
        l.id != ledger.id
            ? l
            : LedgerSummary(
                id: l.id,
                iAmOwner: l.iAmOwner,
                title: l.title,
                subtitle: l.subtitle,
                currency: l.currency,
                myConfirmedMinor: l.myConfirmedMinor,
                myOpenMinor: l.myOpenMinor + delta,
                pendingCount: l.pendingCount + 1,
                disputedCount: l.disputedCount,
                otherPartyJoined: l.otherPartyJoined,
              ),
    ];
  }

  @override
  Future<void> respondEntry(
    String entryId, {
    required bool confirm,
    String? note,
  }) async {
    final to = confirm ? EntryStatus.confirmed : EntryStatus.disputed;
    _act(entryId, to, note);
  }

  @override
  Future<void> voidEntry(String entryId) async =>
      _act(entryId, EntryStatus.voided, null);

  /// Moves an entry to [to] and its ledger's summary with it, like the
  /// ledger_balances view: open = confirmed + pending.
  void _act(String entryId, EntryStatus to, String? note) {
    final error = failNextActionWith;
    if (error != null) {
      failNextActionWith = null;
      throw error;
    }
    actions.add((entryId, to.name, note));
    for (final MapEntry(key: ledgerId, value: list) in entries.entries) {
      final i = list.indexWhere((e) => e.id == entryId);
      if (i < 0) continue;
      final e = list[i];
      entries[ledgerId] = [...list]
        ..[i] = LedgerEntry(
          id: e.id,
          myDeltaMinor: e.myDeltaMinor,
          note: e.note,
          occurredOn: e.occurredOn,
          status: to,
          createdByMe: e.createdByMe,
          responseNote: to == EntryStatus.voided ? e.responseNote : note,
        );
      int counted(EntryStatus s, {required bool open}) => switch (s) {
        EntryStatus.confirmed => e.myDeltaMinor,
        EntryStatus.pending => open ? e.myDeltaMinor : 0,
        _ => 0,
      };
      int count(EntryStatus s, EntryStatus of) => s == of ? 1 : 0;
      final from = e.status;
      ledgers = [
        for (final l in ledgers)
          l.id != ledgerId
              ? l
              : LedgerSummary(
                  id: l.id,
                  iAmOwner: l.iAmOwner,
                  title: l.title,
                  subtitle: l.subtitle,
                  currency: l.currency,
                  myConfirmedMinor:
                      l.myConfirmedMinor -
                      counted(from, open: false) +
                      counted(to, open: false),
                  myOpenMinor:
                      l.myOpenMinor -
                      counted(from, open: true) +
                      counted(to, open: true),
                  pendingCount:
                      l.pendingCount -
                      count(from, EntryStatus.pending) +
                      count(to, EntryStatus.pending),
                  disputedCount:
                      l.disputedCount -
                      count(from, EntryStatus.disputed) +
                      count(to, EntryStatus.disputed),
                  otherPartyJoined: l.otherPartyJoined,
                ),
      ];
      return;
    }
    throw const PostgrestException(message: 'entry not found', code: 'P0002');
  }

  @override
  Future<String> createShareLink(String ledgerId, {int days = 30}) async {
    final error = failNextActionWith;
    if (error != null) {
      failNextActionWith = null;
      throw error;
    }
    return shareLinks[ledgerId] = 'tok${++_tokens}';
  }

  @override
  Future<void> revokeShareLink(String ledgerId) async =>
      shareLinks.remove(ledgerId);

  /// ledger id -> times a reminder was marked sent.
  final reminded = <String, int>{};

  /// (ledger id, name, phone or null) of every counterparty edit.
  final counterpartyEdits = <(String, String, String?)>[];

  @override
  Future<void> updateCounterparty(
    String ledgerId, {
    required String name,
    String? phone,
  }) async {
    final error = failNextActionWith;
    if (error != null) {
      failNextActionWith = null;
      throw error;
    }
    counterpartyEdits.add((ledgerId, name, phone));
    if (phone != null) shareLinks.remove(ledgerId);
    _replace(
      ledgerId,
      (l) => LedgerSummary(
        id: l.id,
        iAmOwner: l.iAmOwner,
        title: name,
        subtitle: l.subtitle,
        currency: l.currency,
        myConfirmedMinor: l.myConfirmedMinor,
        myOpenMinor: l.myOpenMinor,
        pendingCount: l.pendingCount,
        disputedCount: l.disputedCount,
        otherPartyJoined: l.otherPartyJoined,
        remindEveryDays: l.remindEveryDays,
        lastRemindedAt: l.lastRemindedAt,
        counterpartyPhone: phone ?? l.counterpartyPhone,
      ),
    );
  }

  @override
  Future<void> setReminder(String ledgerId, int? days) async =>
      _replace(ledgerId, (l) => _withReminder(l, days, l.lastRemindedAt));

  @override
  Future<void> markReminded(String ledgerId) async {
    reminded.update(ledgerId, (n) => n + 1, ifAbsent: () => 1);
    _replace(
      ledgerId,
      (l) => _withReminder(l, l.remindEveryDays, DateTime.now()),
    );
  }

  void _replace(String id, LedgerSummary Function(LedgerSummary) change) =>
      ledgers = [for (final l in ledgers) l.id == id ? change(l) : l];

  static LedgerSummary _withReminder(
    LedgerSummary l,
    int? days,
    DateTime? last,
  ) => LedgerSummary(
    id: l.id,
    iAmOwner: l.iAmOwner,
    title: l.title,
    subtitle: l.subtitle,
    currency: l.currency,
    myConfirmedMinor: l.myConfirmedMinor,
    myOpenMinor: l.myOpenMinor,
    pendingCount: l.pendingCount,
    disputedCount: l.disputedCount,
    otherPartyJoined: l.otherPartyJoined,
    remindEveryDays: days,
    lastRemindedAt: last,
    counterpartyPhone: l.counterpartyPhone,
  );

  /// Shops holding ledgers: deleting one is refused like the FK does.
  final shopsWithLedgers = <String>{};

  @override
  Future<void> renameBusiness(String id, String name) async {
    final i = businesses.indexWhere((b) => b.id == id);
    if (i < 0) throw StateError('shop not found');
    businesses = [...businesses]..[i] = Business(id: id, name: name);
  }

  @override
  Future<void> deleteBusiness(String id) async {
    if (shopsWithLedgers.contains(id) || opened.any((o) => o.$1 == id)) {
      throw const PostgrestException(message: 'fk', code: '23503');
    }
    if (!businesses.any((b) => b.id == id)) throw StateError('shop not found');
    businesses = businesses.where((b) => b.id != id).toList();
  }

  @override
  Future<List<Business>> fetchMyBusinesses() async {
    final error = failWith;
    if (error != null) throw error;
    return [...businesses]..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<Business> createBusiness(String name) async {
    final shop = Business(id: 'shop-${businesses.length + 1}', name: name);
    businesses = [...businesses, shop];
    return shop;
  }

  /// The currency of every ledger opened, in order.
  final openedCurrencies = <String>[];

  @override
  Future<String> openLedger({
    required String counterpartyName,
    required String phone,
    String? businessId,
    String currency = 'SAR',
  }) async {
    final error = failNextOpenWith;
    if (error != null) {
      failNextOpenWith = null;
      throw error;
    }
    final key = (businessId ?? '', phone);
    if (opened.contains(key)) {
      throw const PostgrestException(message: 'duplicate', code: '23505');
    }
    opened.add(key);
    openedCurrencies.add(currency);
    final id = 'new-${opened.length}';
    final shop = businesses.where((b) => b.id == businessId).firstOrNull;
    ledgers = [
      ...ledgers,
      LedgerSummary(
        id: id,
        iAmOwner: true,
        title: counterpartyName,
        subtitle: shop?.name,
        currency: currency,
        myConfirmedMinor: 0,
        myOpenMinor: 0,
        pendingCount: 0,
        disputedCount: 0,
        otherPartyJoined: false,
      ),
    ];
    return id;
  }
}
