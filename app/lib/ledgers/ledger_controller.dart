import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../core/money.dart';
import '../core/phone_number.dart';
import '../data/ledger_repository.dart';

/// One ledger's screen: its balance from my side, its entries, recording a
/// new entry, and confirming, disputing or withdrawing one. A reload keeps
/// what is on screen while it runs and if it fails.
class LedgerController extends ChangeNotifier {
  LedgerController(
    this._repository,
    this.ledgerId, {
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  final LedgerRepository _repository;
  final String ledgerId;
  final DateTime Function() _now;

  LedgerSummary? _ledger;

  /// Null until the first successful load.
  LedgerSummary? get ledger => _ledger;

  List<LedgerEntry> _entries = const [];
  List<LedgerEntry> get entries => _entries;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// A save or an action on an entry is running.
  bool _saving = false;
  bool get saving => _saving;

  /// The open sheet's error (new entry or entry actions), apart from [error].
  String? _formError;
  String? get formError => _formError;

  bool _disposed = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final ledger = await _repository.fetchLedger(ledgerId);
      final entries = await _repository.fetchEntries(ledger);
      _ledger = ledger;
      _entries = entries;
    } catch (e) {
      _error = arabicMessageFor(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  void clearFormError() {
    _formError = null;
    _notify();
  }

  /// Records an entry dated today; [iGave] is from my side. Returns whether
  /// it was saved. The list reloads after a save; a failed reload shows in
  /// [error] and keeps the old list.
  Future<bool> addEntry({
    required bool iGave,
    required String amount,
    String note = '',
  }) async {
    final ledger = _ledger;
    if (ledger == null || _saving) return false;
    final minor = parseMoney(amount);
    if (minor == null) {
      return _failForm('أدخل مبلغاً صحيحاً، مثل 45.50.');
    }
    final text = note.trim();
    if (text.runes.length > 200) {
      return _failForm('الملاحظة حتى 200 حرف.');
    }
    final now = _now();
    return _write(
      () => _repository.addEntry(
        ledger,
        iGave: iGave,
        amountMinor: minor,
        note: text.isEmpty ? null : text,
        occurredOn: DateTime(now.year, now.month, now.day),
      ),
    );
  }

  Future<bool> confirmEntry(String entryId) =>
      _write(() => _repository.respondEntry(entryId, confirm: true));

  /// A dispute needs its reason, so the creator knows what to correct.
  Future<bool> disputeEntry(String entryId, String reason) async {
    final text = reason.trim();
    if (text.isEmpty || text.runes.length > 200) {
      return _failForm('اكتب سبب الاعتراض (حتى 200 حرف).');
    }
    return _write(
      () => _repository.respondEntry(entryId, confirm: false, note: text),
    );
  }

  Future<bool> withdrawEntry(String entryId) =>
      _write(() => _repository.voidEntry(entryId));

  /// The owner's reminder is due now ([reminderDue]).
  bool get reminderIsDue {
    final ledger = _ledger;
    return ledger != null && reminderDue(ledger, _now());
  }

  /// The owner sets the reminder period: 1..90 days, or null for off.
  Future<bool> setReminder(int? days) async {
    final ledger = _ledger;
    if (ledger == null || !ledger.iAmOwner) return false;
    return _write(() => _repository.setReminder(ledger.id, days));
  }

  /// Makes a fresh share link, hands the reminder message to [copy], then
  /// records the reminder (the server stamps the time). Returns the message,
  /// or null with [formError].
  Future<String?> sendReminder(
    Future<void> Function(String message) copy,
  ) async {
    final ledger = _ledger;
    if (ledger == null || !ledger.iAmOwner) return null;
    final url = await createShareLink();
    if (url == null) return null;
    final message = reminderMessage(ledger, url);
    await copy(message);
    final ok = await _write(() => _repository.markReminded(ledger.id));
    return ok ? message : null;
  }

  /// The owner corrects the other party's name, and their phone until they
  /// join. A new phone drops the share link (the database deletes it).
  Future<bool> updateCounterparty({
    required String name,
    required String phone,
  }) async {
    final ledger = _ledger;
    if (ledger == null || !ledger.iAmOwner) return false;
    final text = name.trim();
    if (text.isEmpty || text.runes.length > 80) {
      return _failForm('اكتب اسم الطرف الآخر (حتى 80 حرفاً).');
    }
    String? newPhone;
    if (!ledger.otherPartyJoined) {
      final normalized = normalizePhone(phone);
      if (normalized == null) return _failForm(invalidPhoneMessage);
      if (normalized == _repository.myPhone) {
        return _failForm('هذا رقمك أنت. أدخل رقم الطرف الآخر.');
      }
      if (normalized != ledger.counterpartyPhone) newPhone = normalized;
    }
    final ok = await _write(
      () => _repository.updateCounterparty(
        ledger.id,
        name: text,
        phone: newPhone,
      ),
      errors: const {
        '55000': 'انضم الطرف الآخر، فلا يتغيّر رقمه بعد الآن.',
        '23505': 'لديك دفتر آخر لهذا الرقم بالفعل.',
      },
    );
    if (ok && newPhone != null) _shareUrl = null;
    return ok;
  }

  String? _shareUrl;

  /// The link created in this screen; null before one is created and after
  /// it is revoked (the token cannot be read back).
  String? get shareUrl => _shareUrl;

  /// Creates a new link for the other party (owner only) and returns it. Any
  /// earlier link stops working.
  Future<String?> createShareLink() async {
    final ledger = _ledger;
    if (ledger == null || !ledger.iAmOwner) return null;
    String? token;
    final ok = await _write(
      () async => token = await _repository.createShareLink(ledger.id),
      reload: false,
    );
    if (!ok) return null;
    _shareUrl = DainConfig.shareUrl(token!);
    _notify();
    return _shareUrl;
  }

  Future<bool> revokeShareLink() async {
    final ledger = _ledger;
    if (ledger == null || !ledger.iAmOwner) return false;
    final ok = await _write(
      () => _repository.revokeShareLink(ledger.id),
      reload: false,
    );
    if (ok) {
      _shareUrl = null;
      _notify();
    }
    return ok;
  }

  /// Runs [action] with [saving] set, then reloads unless [reload] is false
  /// (a share link changes nothing on screen). On failure keeps the
  /// sheet open with [formError]; when the entry changed or vanished under
  /// me (the other side acted first), reloads so the screen shows its state.
  Future<bool> _write(
    Future<void> Function() action, {
    bool reload = true,
    Map<String, String> errors = const {},
  }) async {
    if (_saving) return false;
    _saving = true;
    _formError = null;
    _notify();
    var stale = false;
    try {
      await action();
    } on PostgrestException catch (e) {
      stale = e.code == '55000' || e.code == 'P0002';
      _formError =
          errors[e.code] ??
          switch (e.code) {
            '55000' => 'تغيّرت حالة هذا القيد. أُعيد تحميل الدفتر.',
            'P0002' => 'القيد غير موجود.',
            _ => arabicMessageFor(e),
          };
      return false;
    } catch (e) {
      _formError = arabicMessageFor(e);
      return false;
    } finally {
      _saving = false;
      _notify();
      if (stale) await load();
    }
    if (reload) await load();
    return true;
  }

  bool _failForm(String message) {
    _formError = message;
    _notify();
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
