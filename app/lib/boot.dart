import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app.dart';
import 'ui/brand.dart';

/// The first widget on screen. It draws at once, then runs [init] (Supabase
/// and the session) and shows what [init] returns. A failure or a hang
/// beyond [timeout] is shown on screen with a retry, instead of the launch
/// screen staying blank because main() never reached runApp.
class DainBoot extends StatefulWidget {
  const DainBoot({
    super.key,
    required this.init,
    this.timeout = const Duration(seconds: 20),
  });

  final Future<Widget> Function() init;
  final Duration timeout;

  @override
  State<DainBoot> createState() => _DainBootState();
}

class _DainBootState extends State<DainBoot> {
  Widget? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final app = await widget.init().timeout(widget.timeout);
      if (mounted) setState(() => _app = app);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app != null) return app;
    final error = _error;
    return MaterialApp(
      title: 'دائن',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: DainApp.theme(Brightness.light),
      darkTheme: DainApp.theme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BrandMark(),
                        SizedBox(height: 32),
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('جارٍ البدء…', key: Key('boot_starting')),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'تعذّر بدء التطبيق.',
                          key: Key('boot_failed'),
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 12),
                        // Technical detail, kept selectable for a report.
                        SelectableText(
                          error is TimeoutException
                              ? 'انتهت المهلة أثناء التهيئة.'
                              : '$error',
                          key: const Key('boot_error'),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const Key('boot_retry'),
                          onPressed: _start,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
