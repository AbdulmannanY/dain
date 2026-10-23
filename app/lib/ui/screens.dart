import 'package:flutter/material.dart';

import '../core/phone_number.dart';

import '../session/session_controller.dart';
import 'brand.dart';

/// Shared frame: the brand, the sign-in step, a title and a subtitle, the
/// stage's controls in a card, and the controller's error.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.children,
    this.step,
  });

  final SessionController controller;
  final String title;
  final String subtitle;
  final List<Widget> children;

  /// 0 phone, 1 code, 2 name; null hides the step bar.
  final int? step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = controller.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrandMark(size: 76, showTagline: step == 0),
                  const SizedBox(height: 24),
                  if (step != null) ...[
                    StepBar(step: step!),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...children,
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        error,
                        key: const Key('error_text'),
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.buttonKey,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: buttonKey,
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(label),
    );
  }
}

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() => widget.controller.requestCode(_field.text);

  @override
  Widget build(BuildContext context) {
    return _Frame(
      controller: widget.controller,
      step: 0,
      title: 'ادخل برقم جوالك',
      subtitle:
          'دفتر ديونك مع الناس والمحلات، يؤكّده الطرفان. نرسل لك رمزاً للتحقق.',
      children: [
        TextField(
          key: const Key('phone_field'),
          controller: _field,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(
            labelText: 'رقم الجوال',
            hintText: phoneHint,
            hintTextDirection: TextDirection.ltr,
            prefixIcon: Icon(Icons.phone_iphone),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        _SubmitButton(
          buttonKey: const Key('send_code_button'),
          label: 'أرسل الرمز',
          busy: widget.controller.busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class CodeScreen extends StatefulWidget {
  const CodeScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() => widget.controller.verifyCode(_field.text);

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return _Frame(
      controller: c,
      step: 1,
      title: 'رمز التحقق',
      subtitle: 'أدخل الرمز المرسل إلى \u2066+${c.phone ?? ''}\u2069',
      children: [
        _CodeBoxes(controller: _field, onSubmitted: _submit),
        const SizedBox(height: 16),
        _SubmitButton(
          buttonKey: const Key('verify_button'),
          label: 'تأكيد',
          busy: c.busy,
          onPressed: _submit,
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('change_number_button'),
          onPressed: c.busy ? null : c.changeNumber,
          child: const Text('تغيير الرقم'),
        ),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() => widget.controller.createProfile(_field.text);

  @override
  Widget build(BuildContext context) {
    return _Frame(
      controller: widget.controller,
      step: 2,
      title: 'ما اسمك؟',
      subtitle: 'يظهر اسمك لكل من تسجّل معه دَيناً.',
      children: [
        TextField(
          key: const Key('name_field'),
          controller: _field,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'الاسم',
            counterText: '',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        _SubmitButton(
          buttonKey: const Key('save_profile_button'),
          label: 'متابعة',
          busy: widget.controller.busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class FailedScreen extends StatelessWidget {
  const FailedScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return _Frame(
      controller: controller,
      title: 'تعذّر التحميل',
      subtitle: 'لم نتمكن من تجهيز حسابك.',
      children: [
        _SubmitButton(
          buttonKey: const Key('retry_button'),
          label: 'إعادة المحاولة',
          busy: controller.busy,
          onPressed: controller.retry,
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('sign_out_button'),
          onPressed: controller.busy ? null : controller.signOut,
          child: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }
}

/// Six boxes for the code. One real field (key `code_field`) sits over them,
/// transparent, so typing, pasting and SMS autofill work as usual; the boxes
/// only draw what it holds.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  static const length = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final text = controller.text;
                return Row(
                  children: [
                    for (var i = 0; i < length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          key: Key('code_box_$i'),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: i == text.length
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: i == text.length ? 1.8 : 1,
                            ),
                          ),
                          child: Text(
                            i < text.length ? text[i] : '',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                key: const Key('code_field'),
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                maxLength: length,
                showCursor: false,
                enableInteractiveSelection: false,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(counterText: ''),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Arabic number agreement for "ledgers recorded against your number".
String linkedLedgersMessage(int n) {
  if (n <= 0) return 'لا توجد دفاتر جديدة مسجّلة برقمك.';
  final count = switch (n) {
    1 => 'دفتر واحد مسجّل',
    2 => 'دفتران مسجّلان',
    >= 3 && <= 10 => '$n دفاتر مسجّلة',
    _ => '$n دفتراً مسجّلاً',
  };
  return 'أُضيف إلى حسابك $count برقمك.';
}
