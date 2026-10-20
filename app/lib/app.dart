import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'session/session_controller.dart';
import 'ui/session_gate.dart';

class DainApp extends StatelessWidget {
  const DainApp({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دائن',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: SessionGate(controller: controller),
    );
  }

  static ThemeData _theme(Brightness brightness) {
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
