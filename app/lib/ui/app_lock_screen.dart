import 'package:flutter/material.dart';

import '../core/app_lock.dart';
import 'brand.dart';

/// Gives screens below it (the account screen's switch) the app lock.
class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({
    super.key,
    required AppLockController lock,
    required super.child,
  }) : super(notifier: lock);

  static AppLockController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}

/// Covers the whole app while [lock] is locked and [active] (signed in),
/// without unmounting it, and tells the lock when the app leaves and comes
/// back.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.lock,
    required this.active,
    required this.child,
  });

  final AppLockController lock;
  final bool active;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  late final AppLifecycleListener _life = AppLifecycleListener(
    onHide: widget.lock.hidden,
    onShow: widget.lock.shown,
  );

  @override
  void initState() {
    super.initState();
    _life; // start listening
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLockScope(
      lock: widget.lock,
      child: ListenableBuilder(
        listenable: widget.lock,
        builder: (context, child) => Stack(
          children: [
            child!,
            if (widget.active && widget.lock.locked)
              Positioned.fill(child: _LockScreen(lock: widget.lock)),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.lock});

  final AppLockController lock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('lock_screen'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              const BrandMark(),
              const SizedBox(height: 32),
              Icon(
                Icons.lock_outline,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'دائن مقفل',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'افتحه ببصمتك أو برمز قفل الجوال.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('unlock_button'),
                onPressed: lock.busy ? null : lock.unlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('افتح'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
