import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/ledger_repository.dart';
import '../ledgers/ledgers_controller.dart';
import '../session/session_controller.dart';
import 'common.dart';
import 'ledger_screen.dart';
import 'open_ledger_screen.dart';
import 'shops_screen.dart';
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

  Future<void> _openLedger() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => OpenLedgerScreen(repository: widget.repository),
      ),
    );
    if (id == null || !mounted) return;
    await _showLedger(id);
  }

  /// The ledger's screen; balances may change there, so the list reloads.
  Future<void> _showLedger(String id, [String? title]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LedgerScreen(
          repository: widget.repository,
          ledgerId: id,
          title: title,
        ),
      ),
    );
    if (mounted) await _ledgers.load();
  }

  /// Shop names show on the ledgers, so the list reloads on the way back.
  Future<void> _showShops() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShopsScreen(repository: widget.repository),
      ),
    );
    if (mounted) await _ledgers.load();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_ledger_button'),
        onPressed: _openLedger,
        icon: const Icon(Icons.add),
        label: const Text('دفتر جديد'),
      ),
      appBar: AppBar(
        title: const Text('دفاتري'),
        actions: [
          IconButton(
            key: const Key('shops_button'),
            tooltip: 'محلاتي',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: _showShops,
          ),
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
                : LoadError(message: _ledgers.error!, onRetry: _ledgers.load);
          }
          return RefreshIndicator(
            onRefresh: _ledgers.load,
            child: ListView(
              key: const Key('ledgers_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              // room for the floating button over the last tile
              padding: const EdgeInsets.only(bottom: 88),
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
                  for (final l in list)
                    _LedgerTile(
                      ledger: l,
                      onTap: () => _showLedger(l.id, l.title),
                    ),
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
                    color: owedToMeColor(theme),
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
  const _LedgerTile({required this.ledger, required this.onTap});

  final LedgerSummary ledger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = ledger;
    final v = l.myConfirmedMinor;
    final notes = <String>[
      if (l.subtitle != null) l.subtitle!,
      if (!l.otherPartyJoined) 'لم ينضم بعد',
      if (reminderDue(l, DateTime.now())) 'تذكير مستحق',
      if (l.pendingCount > 0) '${l.pendingCount} بانتظار التأكيد',
      if (l.disputedCount > 0) '${l.disputedCount} معترض عليه',
    ];
    final (label, color) = v > 0
        ? ('لك', owedToMeColor(theme))
        : v < 0
        ? ('عليك', theme.colorScheme.error)
        : ('لا رصيد', theme.colorScheme.onSurfaceVariant);

    return ListTile(
      key: Key('ledger_${l.id}'),
      onTap: onTap,
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
