import 'package:flutter/material.dart';

import '../core/phone_number.dart';
import '../data/ledger_repository.dart';
import '../ledgers/open_ledger_controller.dart';
import 'common.dart';

/// "New ledger": the other party's name and phone, and whether the ledger is
/// personal or under one of my shops (or a new one). Pops with the new
/// ledger's id.
class OpenLedgerScreen extends StatefulWidget {
  const OpenLedgerScreen({super.key, required this.repository});

  final LedgerRepository repository;

  @override
  State<OpenLedgerScreen> createState() => _OpenLedgerScreenState();
}

class _OpenLedgerScreenState extends State<OpenLedgerScreen> {
  late final OpenLedgerController _form = OpenLedgerController(
    widget.repository,
  );
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _shop = TextEditingController();

  @override
  void initState() {
    super.initState();
    _form.load();
  }

  @override
  void dispose() {
    _form.dispose();
    _name.dispose();
    _phone.dispose();
    _shop.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = await _form.submit(
      name: _name.text,
      phone: _phone.text,
      newShopName: _shop.text,
    );
    if (id != null && mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دفتر جديد')),
      body: ListenableBuilder(
        listenable: _form,
        builder: (context, _) {
          final shops = _form.businesses;
          if (shops == null) {
            return _form.error == null
                ? const Center(child: CircularProgressIndicator())
                : LoadError(message: _form.error!, onRetry: _form.load);
          }
          return _buildForm(context, shops);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<Business> shops) {
    final theme = Theme.of(context);
    final owner = _form.owner;
    final error = _form.error;

    Widget chip(Key key, String label, LedgerOwner value, bool selected) =>
        ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected,
          onSelected: (_) => _form.select(value),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('counterparty_name_field'),
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'اسم الطرف الآخر'),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('counterparty_phone_field'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'رقم جواله',
            hintText: phoneHint,
            hintTextDirection: TextDirection.ltr,
            helperText: 'يرى الدفتر عندما يدخل دائن بهذا الرقم.',
          ),
        ),
        const SizedBox(height: 24),
        Text('الدفتر باسم', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(
              const Key('owner_personal'),
              'شخصي',
              const PersonalOwner(),
              owner is PersonalOwner,
            ),
            for (final s in shops)
              chip(
                Key('owner_shop_${s.id}'),
                s.name,
                ShopOwner(s.id),
                owner is ShopOwner && owner.businessId == s.id,
              ),
            chip(
              const Key('owner_new_shop'),
              'محل جديد',
              const NewShopOwner(),
              owner is NewShopOwner,
            ),
          ],
        ),
        if (owner is NewShopOwner) ...[
          const SizedBox(height: 16),
          TextField(
            key: const Key('new_shop_field'),
            controller: _shop,
            decoration: const InputDecoration(labelText: 'اسم المحل'),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error,
            key: const Key('error_text'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('open_ledger_button'),
          onPressed: _form.busy ? null : _submit,
          child: _form.busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('فتح الدفتر'),
        ),
      ],
    );
  }
}
