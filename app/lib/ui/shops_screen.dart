import 'package:flutter/material.dart';

import '../data/ledger_repository.dart';
import '../ledgers/shops_controller.dart';
import 'common.dart';

/// "My shops": tap one to rename it or, when it has no ledgers, delete it.
/// Shops are created from "New ledger".
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key, required this.repository});

  final LedgerRepository repository;

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  late final ShopsController _shops = ShopsController(widget.repository);

  @override
  void initState() {
    super.initState();
    _shops.load();
  }

  @override
  void dispose() {
    _shops.dispose();
    super.dispose();
  }

  Future<void> _edit(Business shop) async {
    _shops.clearFormError();
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ShopSheet(controller: _shops, shop: shop),
    );
    if (done == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('محلاتي')),
      body: ListenableBuilder(
        listenable: _shops,
        builder: (context, _) {
          final list = _shops.shops;
          if (list == null) {
            return _shops.error == null
                ? const Center(child: CircularProgressIndicator())
                : LoadError(message: _shops.error!, onRetry: _shops.load);
          }
          if (list.isEmpty) {
            return Padding(
              key: const Key('shops_empty'),
              padding: const EdgeInsets.all(32),
              child: Text(
                'لا محلات بعد. يُنشأ المحل من «دفتر جديد».',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView(
            key: const Key('shops_list'),
            children: [
              for (final s in list)
                ListTile(
                  key: Key('shop_${s.id}'),
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(s.name),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(s),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Rename, or delete after a second tap. Pops with the message to show.
class _ShopSheet extends StatefulWidget {
  const _ShopSheet({required this.controller, required this.shop});

  final ShopsController controller;
  final Business shop;

  @override
  State<_ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<_ShopSheet> {
  late final _name = TextEditingController(text: widget.shop.name);
  bool _confirmDelete = false;

  @override
  void dispose() {
    _name.dispose();
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
          final busy = c.saving;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.shop.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                key: const Key('shop_name_field'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم المحل'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('save_shop_button'),
                onPressed: busy
                    ? null
                    : () => _run(
                        () => c.rename(widget.shop.id, _name.text),
                        'حُفظ اسم المحل.',
                      ),
                child: const Text('حفظ الاسم'),
              ),
              const SizedBox(height: 8),
              if (_confirmDelete) ...[
                Text(
                  'يُحذف المحل نهائياً. لا يُحذف إن كان فيه دفاتر.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('confirm_delete_shop_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: busy
                      ? null
                      : () =>
                            _run(() => c.delete(widget.shop.id), 'حُذف المحل.'),
                  child: const Text('تأكيد الحذف'),
                ),
              ] else
                OutlinedButton(
                  key: const Key('delete_shop_button'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: busy
                      ? null
                      : () => setState(() => _confirmDelete = true),
                  child: const Text('حذف المحل'),
                ),
              if (c.formError != null) ...[
                const SizedBox(height: 12),
                Text(
                  c.formError!,
                  key: const Key('shop_error_text'),
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
