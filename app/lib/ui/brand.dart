import 'package:flutter/material.dart';

/// Dain's identity, from the owner's logo: deep green and gold.
abstract final class Brand {
  static const green = Color(0xFF0E6B4F);
  static const greenDark = Color(0xFF064A38);
  static const gold = Color(0xFFC9A24A);
  static const tagline = 'إدارة ديونك بكل ثقة';
  static const iconAsset = 'assets/brand/dain_icon.png';
}

/// The app icon with the name and the tagline, for the entry screens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88, this.showTagline = true});

  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('brand_mark'),
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.asset(
            Brand.iconAsset,
            width: size,
            height: size,
            // A missing asset never blocks signing in.
            errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'دائن',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 2),
          Text(
            Brand.tagline,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// "Step [step] of [count]": a segmented bar for the sign-in stages.
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.step, this.count = 3});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: Key('step_bar_$step'),
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 6,
              decoration: BoxDecoration(
                color: i <= step
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
