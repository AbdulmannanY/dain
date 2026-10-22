import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/ledger_repository.dart';
import '../ledgers/dashboard_controller.dart';
import 'common.dart';
import 'ledger_screen.dart';

/// «الملخص المالي»: for each currency apart, what is owed to me and by me,
/// what was collected and paid in a period, what awaits an answer or is
/// disputed, what is overdue or due soon, and who owes me most.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.repository, this.clock});

  final LedgerRepository repository;

  /// For tests; [DateTime.now] otherwise.
  final DateTime Function()? clock;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController _dashboard = DashboardController(
    widget.repository,
    clock: widget.clock,
  );

  @override
  void initState() {
    super.initState();
    _dashboard.load();
  }

  @override
  void dispose() {
    _dashboard.dispose();
    super.dispose();
  }

  /// A debtor's ledger; its balance may change there, so this reloads.
  Future<void> _showLedger(LedgerSummary l) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LedgerScreen(
          repository: widget.repository,
          ledgerId: l.id,
          title: l.title,
        ),
      ),
    );
    if (mounted) await _dashboard.load();
  }

  static const _periods = <(DashboardPeriod, String)>[
    (DashboardPeriod.day, 'اليوم'),
    (DashboardPeriod.week, 'آخر 7 أيام'),
    (DashboardPeriod.month, 'آخر 30 يوماً'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الملخص المالي')),
      body: ListenableBuilder(
        listenable: _dashboard,
        builder: (context, _) {
          final all = _dashboard.dashboards;
          if (all == null) {
            return _dashboard.error == null
                ? const Center(child: CircularProgressIndicator())
                : LoadError(
                    message: _dashboard.error!,
                    onRetry: _dashboard.load,
                  );
          }
          final theme = Theme.of(context);
          return RefreshIndicator(
            onRefresh: _dashboard.load,
            child: ListView(
              key: const Key('dashboard_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_dashboard.error != null) ...[
                  Text(
                    _dashboard.error!,
                    key: const Key('error_text'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                if (all.isEmpty)
                  const Padding(
                    key: Key('dashboard_empty'),
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'لا توجد دفاتر بعد. يظهر الملخص حين تفتح دفتراً '
                      'أو يسجّل غيرك ديناً برقمك.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (period, label) in _periods)
                        ChoiceChip(
                          key: Key('period_${period.name}'),
                          label: Text(label),
                          selected: _dashboard.period == period,
                          onSelected: (_) => _dashboard.choose(period),
                        ),
                    ],
                  ),
                  for (final d in all) ...[
                    const SizedBox(height: 16),
                    _CurrencyCard(dashboard: d, onDebtor: _showLedger),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

String _currencyName(String currency) => switch (currency) {
  'SAR' => 'بالريال السعودي',
  'YER' => 'بالريال اليمني',
  'USD' => 'بالدولار',
  _ => currency,
};

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({required this.dashboard, required this.onDebtor});

  final CurrencyDashboard dashboard;
  final void Function(LedgerSummary) onDebtor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = dashboard;
    final c = d.currency;
    final green = owedToMeColor(theme);
    final red = theme.colorScheme.error;
    String money(int minor) => formatMoney(minor, c);

    return Card(
      key: Key('dashboard_$c'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_currencyName(c), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _Line(
              lineKey: Key('owed_to_me_$c'),
              label: 'لك (متفق عليه)',
              value: money(d.owedToMeMinor),
              color: green,
            ),
            _Line(
              lineKey: Key('i_owe_$c'),
              label: 'عليك (متفق عليه)',
              value: money(d.iOweMinor),
              color: red,
            ),
            const Divider(),
            _Line(
              lineKey: Key('collected_$c'),
              label: 'المحصَّل في الفترة',
              value: money(d.collectedMinor),
              color: green,
            ),
            _Line(
              lineKey: Key('paid_$c'),
              label: 'المدفوع في الفترة',
              value: money(d.paidMinor),
              color: red,
            ),
            const Divider(),
            _Line(
              lineKey: Key('pending_$c'),
              label: 'بانتظار التأكيد (${d.pendingCount})',
              value: money(d.pendingMinor),
            ),
            _Line(
              lineKey: Key('disputed_$c'),
              label: 'معترض عليه (${d.disputedCount})',
              value: money(d.disputedMinor),
            ),
            if (d.overdueToMeMinor != 0)
              _Line(
                lineKey: Key('overdue_to_me_$c'),
                label: 'لك وفات موعده',
                value: money(d.overdueToMeMinor),
                color: red,
              ),
            if (d.overdueIOweMinor != 0)
              _Line(
                lineKey: Key('overdue_i_owe_$c'),
                label: 'عليك وفات موعده',
                value: money(d.overdueIOweMinor),
                color: red,
              ),
            if (d.dueSoonToMeMinor != 0)
              _Line(
                lineKey: Key('due_soon_to_me_$c'),
                label: 'لك يحلّ خلال $dueSoonDays أيام',
                value: money(d.dueSoonToMeMinor),
              ),
            if (d.dueSoonIOweMinor != 0)
              _Line(
                lineKey: Key('due_soon_i_owe_$c'),
                label: 'عليك يحلّ خلال $dueSoonDays أيام',
                value: money(d.dueSoonIOweMinor),
              ),
            if (d.topDebtors.isNotEmpty) ...[
              const Divider(),
              Text('الأكثر مديونية لك', style: theme.textTheme.labelLarge),
              for (final l in d.topDebtors)
                ListTile(
                  key: Key('debtor_${l.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l.title),
                  subtitle: l.subtitle == null ? null : Text(l.subtitle!),
                  trailing: Text(
                    money(l.myConfirmedMinor),
                    style: theme.textTheme.titleSmall?.copyWith(color: green),
                  ),
                  onTap: () => onDebtor(l),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.lineKey,
    required this.label,
    required this.value,
    this.color,
  });

  final Key lineKey;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: lineKey,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
