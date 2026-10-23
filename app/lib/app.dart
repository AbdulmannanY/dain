import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/ledger_repository.dart';
import 'session/session_controller.dart';
import 'ui/brand.dart';
import 'ui/session_gate.dart';

class DainApp extends StatelessWidget {
  const DainApp({super.key, required this.controller, required this.ledgers});

  final SessionController controller;
  final LedgerRepository ledgers;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دائن',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: SessionGate(controller: controller, ledgers: ledgers),
    );
  }

  /// The design system: Dain's green and gold, soft surfaces, rounded
  /// cards and fields, and tall buttons, in light and dark.
  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: Brand.green,
      brightness: brightness,
    );
    final scheme = base.copyWith(
      primary: dark ? const Color(0xFF6FD6AE) : Brand.green,
      onPrimary: dark ? const Color(0xFF00382A) : Colors.white,
      secondary: Brand.gold,
      onSecondary: const Color(0xFF2B2000),
      surface: dark ? const Color(0xFF0D1613) : const Color(0xFFF6F8F7),
      surfaceContainerLow: dark
          ? const Color(0xFF14201C)
          : const Color(0xFFFFFFFF),
      surfaceContainer: dark
          ? const Color(0xFF18261F)
          : const Color(0xFFEFF3F1),
      surfaceContainerHighest: dark
          ? const Color(0xFF22322B)
          : const Color(0xFFE2E9E5),
    );
    final rounded16 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: rounded16,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: rounded16),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded16,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: rounded16,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    );
  }
}
