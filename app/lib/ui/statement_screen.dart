import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money.dart';
import '../data/ledger_repository.dart';
import '../ledgers/statement.dart';
import 'common.dart';

/// «كشف الحساب» of one ledger, from my side: the balance before the
/// period, every agreed movement in it with the balance after each, and the
/// balance at its end. Copies as text (to send) or as CSV (for a sheet).
class StatementScreen extends StatefulWidget {
  const StatementScreen({
    super.key,
    required this.ledger,
    required this.entries,
    this.clock,
  });

  final LedgerSummary ledger;

  /// As the ledger's screen loaded them, newest first.
  final List<LedgerEntry> entries;

  /// For tests; [DateTime.now] otherwise.
  final DateTime Function()? clock;

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  StatementPeriod _period = StatementPeriod.thisMonth;

  static const _periods = <(StatementPeriod, String)>[
    (StatementPeriod.thisMonth, 'هذا الشهر'),
    (StatementPeriod.lastMonth, 'الشهر الماضي'),
    (StatementPeriod.thisYear, 'هذه السنة'),
    (StatementPeriod.all, 'كل الحركات'),
  ];

  Statement get _statement {
    final range = statementRange(_period, (widget.clock ?? DateTime.now)());
    return buildStatement(
      widget.ledger,
      widget.entries,
      from: range.from,
      to: range.to,
    );
  }

  Future<void> _copy(String text, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _statement;
    final c = widget.ledger.currency;
    Color colorOf(int minor) => minor > 0
        ? owedToMeColor(theme)
        : minor < 0
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text('كشف حساب ${widget.ledger.title}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('copy_statement_button'),
                  onPressed: () => _copy(
                    statementText(s),
                    'نُسخ الكشف. أرسله عبر واتساب أو رسالة.',
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ الكشف'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('copy_csv_button'),
                  onPressed: () => _copy(
                    statementCsv(s),
                    'نُسخ الكشف CSV. الصقه في جدول بيانات.',
                  ),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('نسخ CSV'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        key: const Key('statement_list'),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (period, label) in _periods)
                ChoiceChip(
                  key: Key('statement_${period.name}'),
                  label: Text(label),
                  selected: _period == period,
                  onSelected: (_) => setState(() => _period = period),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.from == null
                ? 'حتى ${shortDay(s.to)}'
                : 'من ${shortDay(s.from!)} إلى ${shortDay(s.to)}',
            key: const Key('statement_span'),
            style: theme.textTheme.labelLarge,
          ),
          _BalanceRow(
            rowKey: const Key('statement_opening'),
            label: 'الرصيد السابق',
            value: balanceWords(s.openingMinor, c),
            color: colorOf(s.openingMinor),
          ),
          const Divider(),
          if (s.lines.isEmpty)
            const Padding(
              key: Key('statement_empty'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'لا حركات مؤكدة في هذه الفترة.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final line in s.lines)
            ListTile(
              key: Key('statement_line_${line.entry.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '${movementVerb(line.entry)} '
                '${formatMoney(line.entry.myDeltaMinor, c)}',
              ),
              subtitle: Text(
                [
                  shortDay(line.entry.occurredOn),
                  if (line.entry.note != null) line.entry.note!,
                ].join(' · '),
              ),
              trailing: Text(
                balanceWords(line.balanceMinor, c),
                style: TextStyle(color: colorOf(line.balanceMinor)),
              ),
            ),
          const Divider(),
          _BalanceRow(
            rowKey: const Key('statement_totals'),
            label: 'زاد ما لك / نقص',
            value:
                '${formatMoney(s.increasedMinor, c)} / '
                '${formatMoney(s.decreasedMinor, c)}',
          ),
          _BalanceRow(
            rowKey: const Key('statement_closing'),
            label: 'الرصيد النهائي',
            value: balanceWords(s.closingMinor, c),
            color: colorOf(s.closingMinor),
          ),
          if (s.unconfirmedCount > 0)
            Padding(
              key: const Key('statement_unconfirmed'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'لا يشمل قيوداً لم تُؤكَّد بعد: ${s.unconfirmedCount}.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.rowKey,
    required this.label,
    required this.value,
    this.color,
  });

  final Key rowKey;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: rowKey,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
