import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/ledger_repository.dart';
import '../ledgers/ledgers_controller.dart';
import '../session/session_controller.dart';
import 'screens.dart';

/// The signed-in home: every ledger I own or am linked to, with the agreed
/// balance from my side and what still awaits confirmation.
class LedgersScreen extends StatefulWidget {
  const LedgersScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final LedgerRepository repository;

  @override
  State<LedgersScreen> createState() => _LedgersScreenState();
}

class _LedgersScreenState extends State<LedgersScreen> {
  late final LedgersController _ledgers = LedgersController(widget.repository);

  @override
  void initState() {
    super.initState();
    _ledgers.load();
  }

  @override
  void dispose() {
    _ledgers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفاتري'),
        actions: [
          IconButton(
            key: const Key('sign_out_button'),
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: session.busy ? null : session.signOut,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _ledgers,
        builder: (context, _) {
          final list = _ledgers.ledgers;
          if (list == null) {
            return _ledgers.error == null
                ? const Center(child: CircularProgressIndicator())
                : _LoadError(message: _ledgers.error!, onRetry: _ledgers.load);
          }
          return RefreshIndicator(
            onRefresh: _ledgers.load,
            child: ListView(
              key: const Key('ledgers_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _Header(
                  name: session.profile?.fullName ?? '',
                  linkedCount: session.linkedCount ?? 0,
                  totals: _ledgers.totals,
                  refreshError: _ledgers.error,
                ),
                if (list.isEmpty)
                  const _Empty()
                else
                  for (final l in list) _LedgerTile(ledger: l),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.linkedCount,
    required this.totals,
    required this.refreshError,
  });

  final String name;
  final int linkedCount;
  final List<BalanceTotal> totals;
  final String? refreshError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('أهلاً، $name', style: theme.textTheme.titleLarge),
          if (linkedCount > 0) ...[
            const SizedBox(height: 12),
            Card(
              key: const Key('linked_banner'),
              color: theme.colorScheme.secondaryContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(linkedLedgersMessage(linkedCount)),
              ),
            ),
          ],
          if (refreshError != null) ...[
            const SizedBox(height: 12),
            Text(
              refreshError!,
              key: const Key('error_text'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          for (final t in totals) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TotalBox(
                    boxKey: Key('total_owed_to_me_${t.currency}'),
                    label: 'لك',
                    amount: formatMoney(t.owedToMeMinor, t.currency),
                    color: _owedToMeColor(theme),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TotalBox(
                    boxKey: Key('total_i_owe_${t.currency}'),
                    label: 'عليك',
                    amount: formatMoney(t.iOweMinor, t.currency),
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalBox extends StatelessWidget {
  const _TotalBox({
    required this.boxKey,
    required this.label,
    required this.amount,
    required this.color,
  });

  final Key boxKey;
  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: boxKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              amount,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.ledger});

  final LedgerSummary ledger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = ledger;
    final v = l.myConfirmedMinor;
    final notes = <String>[
      if (l.subtitle != null) l.subtitle!,
      if (!l.otherPartyJoined) 'لم ينضم بعد',
      if (l.pendingCount > 0) '${l.pendingCount} بانتظار التأكيد',
      if (l.disputedCount > 0) '${l.disputedCount} معترض عليه',
    ];
    final (label, color) = v > 0
        ? ('لك', _owedToMeColor(theme))
        : v < 0
        ? ('عليك', theme.colorScheme.error)
        : ('لا رصيد', theme.colorScheme.onSurfaceVariant);

    return ListTile(
      key: Key('ledger_${l.id}'),
      leading: CircleAvatar(
        child: Icon(
          l.subtitle != null && !l.iAmOwner ? Icons.store : Icons.person,
        ),
      ),
      title: Text(l.title),
      subtitle: notes.isEmpty ? null : Text(notes.join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
          if (v != 0)
            Text(
              formatMoney(v, l.currency),
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('ledgers_empty'),
      padding: const EdgeInsets.all(32),
      child: Text(
        'لا توجد دفاتر بعد. ستظهر هنا الدفاتر التي تفتحها، '
        'والتي يسجّلها غيرك برقم جوالك.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              key: const Key('error_text'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('retry_button'),
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

Color _owedToMeColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFF7FD8B0)
    : const Color(0xFF0E6B4F);
