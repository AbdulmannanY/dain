import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/ledger_repository.dart';
import '../ledgers/ledger_controller.dart';
import 'common.dart';

/// One ledger: the agreed balance from my side, the entries newest first,
/// "أعطيت" / "أخذت" to record a new one, and tapping an entry to confirm,
/// dispute or withdraw it.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({
    super.key,
    required this.repository,
    required this.ledgerId,
    this.title,
  });

  final LedgerRepository repository;
  final String ledgerId;

  /// Shown until the ledger loads.
  final String? title;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late final LedgerController _ledger = LedgerController(
    widget.repository,
    widget.ledgerId,
  );

  @override
  void initState() {
    super.initState();
    _ledger.load();
  }

  @override
  void dispose() {
    _ledger.dispose();
    super.dispose();
  }

  Future<void> _record(bool iGave) async {
    _ledger.clearFormError();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntrySheet(controller: _ledger, iGave: iGave),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('سُجّل القيد. ينتظر تأكيد الطرف الآخر.')),
    );
  }

  Future<void> _showEntry(LedgerEntry entry, String currency) async {
    _ledger.clearFormError();
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntryActionsSheet(
        controller: _ledger,
        entry: entry,
        currency: currency,
      ),
    );
    if (done == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ledger,
      builder: (context, _) {
        final ledger = _ledger.ledger;
        return Scaffold(
          appBar: AppBar(title: Text(ledger?.title ?? widget.title ?? '')),
          bottomNavigationBar: ledger == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('add_gave_button'),
                            onPressed: () => _record(true),
                            icon: const Icon(Icons.call_made),
                            label: const Text('أعطيت'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const Key('add_took_button'),
                            onPressed: () => _record(false),
                            icon: const Icon(Icons.call_received),
                            label: const Text('أخذت'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          body: ledger == null
              ? (_ledger.error == null
                    ? const Center(child: CircularProgressIndicator())
                    : LoadError(message: _ledger.error!, onRetry: _ledger.load))
              : RefreshIndicator(
                  onRefresh: _ledger.load,
                  child: ListView(
                    key: const Key('entries_list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _Balance(ledger: ledger, refreshError: _ledger.error),
                      if (_ledger.entries.isEmpty)
                        const _Empty()
                      else
                        for (final e in _ledger.entries)
                          _EntryTile(
                            entry: e,
                            currency: ledger.currency,
                            onTap: () => _showEntry(e, ledger.currency),
                          ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.ledger, required this.refreshError});

  final LedgerSummary ledger;
  final String? refreshError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = ledger;
    final v = l.myConfirmedMinor;
    final (label, color) = v > 0
        ? ('لك', owedToMeColor(theme))
        : v < 0
        ? ('عليك', theme.colorScheme.error)
        : ('لا رصيد', theme.colorScheme.onSurfaceVariant);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final open = l.myOpenMinor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        key: const Key('ledger_balance'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (l.subtitle != null) Text(l.subtitle!, style: muted),
              Text(label, style: theme.textTheme.labelLarge),
              if (v != 0)
                Text(
                  formatMoney(v, l.currency),
                  style: theme.textTheme.headlineSmall?.copyWith(color: color),
                ),
              if (open != v)
                Text(
                  'مع المعلّق: ${_side(open)}'
                  '${open == 0 ? '' : ' ${formatMoney(open, l.currency)}'}',
                  style: muted,
                ),
              if (l.pendingCount > 0)
                Text('${l.pendingCount} بانتظار التأكيد', style: muted),
              if (l.disputedCount > 0)
                Text('${l.disputedCount} معترض عليه', style: muted),
              if (!l.otherPartyJoined) ...[
                const SizedBox(height: 8),
                Text(
                  'لم ينضم بعد. تبقى القيود بانتظار تأكيده حتى يدخل دائن '
                  'برقمه.',
                  key: const Key('not_joined_note'),
                  style: muted,
                ),
              ],
              if (refreshError != null) ...[
                const SizedBox(height: 8),
                Text(
                  refreshError!,
                  key: const Key('error_text'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _side(int minor) => minor > 0
    ? 'لك'
    : minor < 0
    ? 'عليك'
    : 'لا رصيد';

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.currency,
    required this.onTap,
  });

  final LedgerEntry entry;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final voided = e.status == EntryStatus.voided;

    return ListTile(
      key: Key('entry_${e.id}'),
      onTap: onTap,
      leading: CircleAvatar(
        child: Icon(e.myDeltaMinor > 0 ? Icons.call_made : Icons.call_received),
      ),
      title: Text(
        _entryTitle(e, currency),
        style: voided
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: Text(_entryDetails(e).join(' · ')),
    );
  }
}

String _entryTitle(LedgerEntry e, String currency) =>
    '${e.myDeltaMinor > 0 ? 'أعطيت' : 'أخذت'} '
    '${formatMoney(e.myDeltaMinor, currency)}';

List<String> _entryDetails(LedgerEntry e) {
  final d = e.occurredOn;
  return [
    if (e.note != null) e.note!,
    '${d.day}/${d.month}/${d.year}',
    e.createdByMe ? 'سجّلته أنت' : 'سجّله الطرف الآخر',
    switch (e.status) {
      EntryStatus.pending =>
        e.createdByMe ? 'بانتظار التأكيد' : 'بانتظار تأكيدك',
      EntryStatus.confirmed => 'مؤكد',
      EntryStatus.disputed => 'معترض عليه',
      EntryStatus.voided => 'مسحوب',
    },
    if (e.responseNote != null) 'الرد: ${e.responseNote}',
  ];
}

/// One entry's details and what I may do with it ([entryActions]). Pops
/// with the message to show once an action went through.
class _EntryActionsSheet extends StatefulWidget {
  const _EntryActionsSheet({
    required this.controller,
    required this.entry,
    required this.currency,
  });

  final LedgerController controller;
  final LedgerEntry entry;
  final String currency;

  @override
  State<_EntryActionsSheet> createState() => _EntryActionsSheetState();
}

class _EntryActionsSheetState extends State<_EntryActionsSheet> {
  final _reason = TextEditingController();

  /// The second step of a dispute (the reason) or a withdrawal (the warning).
  EntryAction? _step;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action, String done) async {
    final ok = await action();
    if (ok && mounted) Navigator.of(context).pop(done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          // After a reload the entry may have changed under me.
          final e = c.entries.firstWhere(
            (x) => x.id == widget.entry.id,
            orElse: () => widget.entry,
          );
          final actions = entryActions(e);
          // A step the entry no longer allows (it changed) is dropped.
          final step = actions.contains(_step) ? _step : null;
          final muted = theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );
          final busy = c.saving;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _entryTitle(e, widget.currency),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(_entryDetails(e).join(' · '), style: muted),
              const SizedBox(height: 16),
              if (actions.isEmpty)
                Text(
                  e.status == EntryStatus.confirmed
                      ? 'قيد مؤكد لا يُعدَّل. للتصحيح سجّل قيداً معاكساً.'
                      : 'قيد مسحوب.',
                  key: const Key('entry_final_note'),
                  style: muted,
                ),
              if (step == EntryAction.dispute) ...[
                TextField(
                  key: const Key('dispute_reason_field'),
                  controller: _reason,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'سبب الاعتراض'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('send_dispute_button'),
                  onPressed: busy
                      ? null
                      : () => _run(
                          () => c.disputeEntry(e.id, _reason.text),
                          'أُرسل الاعتراض.',
                        ),
                  child: const Text('إرسال الاعتراض'),
                ),
              ] else if (step == EntryAction.withdraw) ...[
                Text(
                  'سحب القيد نهائي، ولا يدخل في أي رصيد بعده.',
                  style: muted,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('confirm_withdraw_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: busy
                      ? null
                      : () => _run(() => c.withdrawEntry(e.id), 'سُحب القيد.'),
                  child: const Text('تأكيد السحب'),
                ),
              ] else ...[
                if (actions.contains(EntryAction.confirm))
                  FilledButton(
                    key: const Key('confirm_entry_button'),
                    onPressed: busy
                        ? null
                        : () =>
                              _run(() => c.confirmEntry(e.id), 'أُكّد القيد.'),
                    child: const Text('تأكيد'),
                  ),
                if (actions.contains(EntryAction.dispute)) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('dispute_entry_button'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: busy
                        ? null
                        : () => setState(() => _step = EntryAction.dispute),
                    child: const Text('اعتراض'),
                  ),
                ],
                if (actions.contains(EntryAction.withdraw))
                  OutlinedButton(
                    key: const Key('withdraw_entry_button'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: busy
                        ? null
                        : () => setState(() => _step = EntryAction.withdraw),
                    child: const Text('سحب القيد'),
                  ),
              ],
              if (c.formError != null) ...[
                const SizedBox(height: 12),
                Text(
                  c.formError!,
                  key: const Key('entry_error_text'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('entries_empty'),
      padding: const EdgeInsets.all(32),
      child: Text(
        'لا قيود بعد. سجّل ما أعطيته أو أخذته، ويؤكده الطرف الآخر.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// The amount and note of a new entry. Pops true once saved.
class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.controller, required this.iGave});

  final LedgerController controller;
  final bool iGave;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await widget.controller.addEntry(
      iGave: widget.iGave,
      amount: _amount.text,
      note: _note.text,
    );
    if (saved && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    final currency = c.ledger?.currency ?? 'SAR';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.iGave ? 'أعطيت' : 'أخذت',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              widget.iGave
                  ? 'مبلغ أو بضاعة أعطيتها له. يزيد ما لك عليه.'
                  : 'مبلغ أو بضاعة أخذتها منه، أو سداد منه. يقلّ ما لك عليه.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('amount_field'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'المبلغ',
                suffixText: currency == 'SAR' ? 'ر.س' : currency,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('note_field'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختيارية)'),
            ),
            if (c.formError != null) ...[
              const SizedBox(height: 12),
              Text(
                c.formError!,
                key: const Key('entry_error_text'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'يبقى القيد بانتظار تأكيد الطرف الآخر.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('save_entry_button'),
              onPressed: c.saving ? null : _save,
              child: c.saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
