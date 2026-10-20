import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../data/ledger_repository.dart';

/// Loads the signed-in person's ledgers. A refresh keeps the last list on
/// screen while it runs and if it fails.
class LedgersController extends ChangeNotifier {
  LedgersController(this._repository);

  final LedgerRepository _repository;

  List<LedgerSummary>? _ledgers;

  /// Null until the first successful load.
  List<LedgerSummary>? get ledgers => _ledgers;

  List<BalanceTotal> get totals => totalsByCurrency(_ledgers ?? const []);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  bool _disposed = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _ledgers = await _repository.fetchMine();
    } catch (e) {
      _error = arabicMessageFor(e);
    } finally {
      _loading = false;
      _notify();
    }
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
