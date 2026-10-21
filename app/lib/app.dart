import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/ledger_repository.dart';
import 'session/session_controller.dart';
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

  static ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0E6B4F),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    );
  }
}
