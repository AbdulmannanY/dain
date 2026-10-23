import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/open_url.dart';
import '../session/session_controller.dart';
import 'app_lock_screen.dart';

/// "My account": my name as others see it, the privacy policy, and
/// deleting the account.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final _name = TextEditingController(
    text: widget.session.profile?.fullName ?? '',
  );
  bool _confirmDelete = false;
  bool _saved = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    setState(() => _saved = false);
    final ok = await widget.session.rename(_name.text);
    if (ok && mounted) setState(() => _saved = true);
  }

  Future<void> _privacy() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await openUrl(Uri.parse(DainConfig.privacyUrl))) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذّر فتح الصفحة: ${DainConfig.privacyUrl}'),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final ok = await widget.session.deleteAccount();
    // Back to the first screen, which is now the phone screen.
    if (ok) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final s = widget.session;
          final busy = s.busy;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: const Key('account_name_field'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'اسمك',
                  helperText: 'يظهر لكل من تسجّل معه ديناً.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('save_name_button'),
                onPressed: busy ? null : _rename,
                child: const Text('حفظ الاسم'),
              ),
              if (_saved) ...[
                const SizedBox(height: 8),
                Text(
                  'حُفظ الاسم.',
                  key: const Key('name_saved_text'),
                  style: muted,
                ),
              ],
              if (s.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  s.error!,
                  key: const Key('error_text'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              ListTile(
                key: const Key('privacy_link'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('سياسة الخصوصية'),
                subtitle: const Text('ما نحفظه ومن يراه، وتفتح في المتصفح.'),
                onTap: _privacy,
              ),
              if (AppLockScope.maybeOf(context) case final lock?)
                SwitchListTile(
                  key: const Key('app_lock_switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('قفل التطبيق بالبصمة'),
                  subtitle: const Text(
                    'يُطلب عند الفتح وبعد 30 ثانية في الخلفية. يعمل برمز الجوال إن لم توجد بصمة.',
                  ),
                  value: lock.enabled,
                  onChanged: lock.busy
                      ? null
                      : (on) async {
                          final messenger = ScaffoldMessenger.of(context);
                          final why = await lock.setEnabled(on);
                          if (why != null) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(why)),
                            );
                          }
                        },
                ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text('حذف الحساب', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'نهائي ولا يمكن التراجع عنه: يُحذف اسمك ومحلاتك والدفاتر التي '
                'فتحتها أنت بقيودها. أما الدفاتر التي فتحها غيرك معك فتبقى عندهم '
                'بقيودها كسجل لهم، وتُفصل عنك.',
                style: muted,
              ),
              const SizedBox(height: 12),
              if (_confirmDelete)
                FilledButton(
                  key: const Key('confirm_delete_account_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: busy ? null : _delete,
                  child: const Text('تأكيد حذف الحساب نهائياً'),
                )
              else
                OutlinedButton(
                  key: const Key('delete_account_button'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: busy
                      ? null
                      : () => setState(() => _confirmDelete = true),
                  child: const Text('حذف الحساب'),
                ),
            ],
          );
        },
      ),
    );
  }
}
