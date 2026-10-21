import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors.dart';
import '../core/money.dart';
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

  /// Runs [action] with [saving] set, then reloads. On failure keeps the
  /// sheet open with [formError]; when the entry changed or vanished under
  /// me (the other side acted first), reloads so the screen shows its state.
  Future<bool> _write(Future<void> Function() action) async {
    if (_saving) return false;
    _saving = true;
    _formError = null;
    _notify();
    var stale = false;
    try {
      await action();
    } on PostgrestException catch (e) {
      stale = e.code == '55000' || e.code == 'P0002';
      _formError = switch (e.code) {
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
    await load();
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
