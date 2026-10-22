import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../data/ledger_repository.dart';

/// How «دفاتري» orders the ledgers.
enum LedgerSort {
  /// The size of the agreed balance, largest first (as loaded).
  balance,

  /// By the other party's name.
  name,

  /// Ledgers with pending or disputed entries first, the most first.
  open,

  /// The nearest repayment day first (overdue ones lead); none last.
  due,
}

/// Folds what people type differently into one form, so a search finds
/// «أحمد» from «احمد» and «فاطمة» from «فاطمه»: lower case, no diacritics
/// or tatweel, one alef, ه for ة, ي for ى and ئ, و for ؤ, and Arabic-Indic
/// or Persian digits as ASCII.
String searchKey(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if ((rune >= 0x064B && rune <= 0x0652) || rune == 0x0670) continue;
    if (rune == 0x0640) continue; // tatweel
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.write(rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.write(rune - 0x06F0);
    } else {
      buffer.writeCharCode(switch (rune) {
        0x0622 || 0x0623 || 0x0625 || 0x0671 => 0x0627, // آ أ إ ٱ -> ا
        0x0629 => 0x0647, // ة -> ه
        0x0649 || 0x0626 => 0x064A, // ى ئ -> ي
        0x0624 => 0x0648, // ؤ -> و
        _ => rune,
      });
    }
  }
  return buffer.toString();
}

/// Whether [l] matches what was typed: every word of [query] is in the
/// title or the subtitle, or the digits typed (2 or more, a leading 0 of a
/// local number dropped) are in the other party's phone. An empty query
/// matches everything.
bool ledgerMatches(LedgerSummary l, String query) {
  final key = searchKey(query).trim();
  if (key.isEmpty) return true;
  final digits = key.replaceAll(RegExp(r'[^0-9]'), '');
  final phone = l.counterpartyPhone;
  if (phone != null &&
      digits.length >= 2 &&
      RegExp(r'^[0-9+\s-]+$').hasMatch(key) &&
      phone.contains(digits.replaceFirst(RegExp('^0+'), ''))) {
    return true;
  }
  final haystack = searchKey('${l.title} ${l.subtitle ?? ''}');
  return key.split(RegExp(r'\s+')).every(haystack.contains);
}

/// [ledgers] that match [query], in [sort] order. Ties keep the loaded
/// order (balance size, then name).
List<LedgerSummary> searchLedgers(
  List<LedgerSummary> ledgers, {
  String query = '',
  LedgerSort sort = LedgerSort.balance,
}) {
  final found = [
    for (final (i, l) in ledgers.indexed)
      if (ledgerMatches(l, query)) (i, l),
  ];
  int open(LedgerSummary l) => l.pendingCount + l.disputedCount;
  found.sort((x, y) {
    final by = switch (sort) {
      LedgerSort.balance => 0,
      LedgerSort.name => searchKey(x.$2.title).compareTo(searchKey(y.$2.title)),
      LedgerSort.open => open(y.$2).compareTo(open(x.$2)),
      LedgerSort.due => switch ((x.$2.dueOn, y.$2.dueOn)) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        (final a?, final b?) => a.compareTo(b),
      },
    };
    return by != 0 ? by : x.$1.compareTo(y.$1);
  });
  return [for (final (_, l) in found) l];
}

/// Loads the signed-in person's ledgers. A refresh keeps the last list on
/// screen while it runs and if it fails. Searching and sorting work on the
/// loaded list; the totals always cover every ledger.
class LedgersController extends ChangeNotifier {
  LedgersController(this._repository);

  final LedgerRepository _repository;

  List<LedgerSummary>? _ledgers;

  /// Null until the first successful load.
  List<LedgerSummary>? get ledgers => _ledgers;

  /// The loaded ledgers that match [query], in [sort] order.
  List<LedgerSummary>? get visible {
    final all = _ledgers;
    return all == null ? null : searchLedgers(all, query: _query, sort: _sort);
  }

  List<BalanceTotal> get totals => totalsByCurrency(_ledgers ?? const []);

  String _query = '';
  String get query => _query;

  LedgerSort _sort = LedgerSort.balance;
  LedgerSort get sort => _sort;

  void search(String query) {
    _query = query;
    _notify();
  }

  void sortBy(LedgerSort sort) {
    _sort = sort;
    _notify();
  }

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
