import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../data/ledger_repository.dart';

/// The span the collected and paid amounts cover, ending today.
enum DashboardPeriod {
  /// Today only.
  day(1),

  /// Today and the 6 days before it.
  week(7),

  /// Today and the 29 days before it.
  month(30);

  const DashboardPeriod(this.days);

  final int days;
}

/// How many days ahead a repayment day counts as "due soon".
const dueSoonDays = 7;

/// How many of the largest debtors each currency lists.
const topDebtorsCount = 3;

/// The dashboard of one currency, from my side. Currencies are never added
/// together: a riyal of Yemen is not a Saudi riyal.
class CurrencyDashboard {
  const CurrencyDashboard({
    required this.currency,
    required this.owedToMeMinor,
    required this.iOweMinor,
    required this.collectedMinor,
    required this.paidMinor,
    required this.pendingMinor,
    required this.pendingCount,
    required this.disputedMinor,
    required this.disputedCount,
    required this.overdueToMeMinor,
    required this.overdueIOweMinor,
    required this.dueSoonToMeMinor,
    required this.dueSoonIOweMinor,
    required this.topDebtors,
  });

  final String currency;

  /// Agreed balances (confirmed by both sides): owed to me, and by me.
  final int owedToMeMinor;
  final int iOweMinor;

  /// Confirmed payments in the period: received by me, and made by me.
  final int collectedMinor;
  final int paidMinor;

  /// Entries still awaiting an answer, and disputed ones: their amounts
  /// added up whatever their direction, apart from the agreed balance.
  final int pendingMinor;
  final int pendingCount;
  final int disputedMinor;
  final int disputedCount;

  /// Agreed balances whose repayment day has passed, owed to me and by me.
  final int overdueToMeMinor;
  final int overdueIOweMinor;

  /// Agreed balances due from today to [dueSoonDays] days ahead.
  final int dueSoonToMeMinor;
  final int dueSoonIOweMinor;

  /// The ledgers that owe me most in this currency, largest first.
  final List<LedgerSummary> topDebtors;
}

/// Builds the dashboard of each currency I have a ledger in, sorted by
/// currency code, from [ledgers] (agreed balances, repayment days) and
/// [flows] (payments by day, pending and disputed). [today] is the local
/// day; payments count when their day is in [period] up to [today].
List<CurrencyDashboard> buildDashboards({
  required List<LedgerSummary> ledgers,
  required List<LedgerFlow> flows,
  required DashboardPeriod period,
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final currencyOf = {for (final l in ledgers) l.id: l.currency};
  final currencies = currencyOf.values.toSet().toList()..sort();
  return [
    for (final c in currencies)
      _dashboardOf(
        c,
        [
          for (final l in ledgers)
            if (l.currency == c) l,
        ],
        [
          for (final f in flows)
            if (currencyOf[f.ledgerId] == c) f,
        ],
        from: DateTime(day.year, day.month, day.day - (period.days - 1)),
        today: day,
      ),
  ];
}

CurrencyDashboard _dashboardOf(
  String currency,
  List<LedgerSummary> ledgers,
  List<LedgerFlow> flows, {
  required DateTime from,
  required DateTime today,
}) {
  final soon = DateTime(today.year, today.month, today.day + dueSoonDays);
  var owedToMe = 0, iOwe = 0, collected = 0, paid = 0;
  var pending = 0, pendingCount = 0, disputed = 0, disputedCount = 0;
  var overdueToMe = 0, overdueIOwe = 0, soonToMe = 0, soonIOwe = 0;
  for (final l in ledgers) {
    final v = l.myConfirmedMinor;
    if (v > 0) owedToMe += v;
    if (v < 0) iOwe -= v;
    final due = l.dueOn;
    if (due == null || v == 0) continue;
    if (paymentOverdue(l, today)) {
      if (v > 0) {
        overdueToMe += v;
      } else {
        overdueIOwe -= v;
      }
    } else if (!due.isAfter(soon)) {
      if (v > 0) {
        soonToMe += v;
      } else {
        soonIOwe -= v;
      }
    }
  }
  for (final f in flows) {
    final amount = f.myDeltaMinor.abs();
    switch (f.status) {
      case EntryStatus.confirmed:
        final on = f.paidOn;
        if (on == null || on.isBefore(from) || on.isAfter(today)) continue;
        // A payment I made is what I gave: positive from my side.
        if (f.myDeltaMinor > 0) {
          paid += amount;
        } else {
          collected += amount;
        }
      case EntryStatus.pending:
        pending += amount;
        pendingCount += f.count;
      case EntryStatus.disputed:
        disputed += amount;
        disputedCount += f.count;
      case EntryStatus.voided:
        continue;
    }
  }
  final debtors = [
    for (final l in ledgers)
      if (l.myConfirmedMinor > 0) l,
  ]..sort((a, b) => b.myConfirmedMinor.compareTo(a.myConfirmedMinor));
  return CurrencyDashboard(
    currency: currency,
    owedToMeMinor: owedToMe,
    iOweMinor: iOwe,
    collectedMinor: collected,
    paidMinor: paid,
    pendingMinor: pending,
    pendingCount: pendingCount,
    disputedMinor: disputed,
    disputedCount: disputedCount,
    overdueToMeMinor: overdueToMe,
    overdueIOweMinor: overdueIOwe,
    dueSoonToMeMinor: soonToMe,
    dueSoonIOweMinor: soonIOwe,
    topDebtors: debtors.take(topDebtorsCount).toList(),
  );
}

/// «الملخص المالي»: loads my ledgers and their flows for the longest
/// period once, then shows the chosen [period] without another read.
class DashboardController extends ChangeNotifier {
  DashboardController(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LedgerRepository _repository;
  final DateTime Function() _clock;

  List<LedgerSummary>? _ledgers;
  List<LedgerFlow> _flows = const [];

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  DashboardPeriod _period = DashboardPeriod.month;
  DashboardPeriod get period => _period;

  bool _disposed = false;

  DateTime get _today {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  /// Null until the first successful load.
  List<CurrencyDashboard>? get dashboards {
    final ledgers = _ledgers;
    if (ledgers == null) return null;
    return buildDashboards(
      ledgers: ledgers,
      flows: _flows,
      period: _period,
      today: _today,
    );
  }

  /// Loads again; a failed reload keeps what was shown, with [error].
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final today = _today;
      final since = DateTime(
        today.year,
        today.month,
        today.day - (DashboardPeriod.month.days - 1),
      );
      final ledgers = await _repository.fetchMine();
      final flows = await _repository.fetchFlows(ledgers, since: since);
      _ledgers = ledgers;
      _flows = flows;
    } catch (e) {
      _error = arabicMessageFor(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  void choose(DashboardPeriod period) {
    if (period == _period) return;
    _period = period;
    _notify();
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
