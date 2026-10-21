import 'package:flutter/material.dart';

/// Green for what the other party owes me ("لك").
Color owedToMeColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFF7FD8B0)
    : const Color(0xFF0E6B4F);

/// A first load that failed: the message and a retry button.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, required this.onRetry});

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
