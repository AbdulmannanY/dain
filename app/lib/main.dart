import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'boot.dart';
import 'core/config.dart';
import 'data/auth_repository.dart';
import 'data/ledger_repository.dart';
import 'data/profile_repository.dart';
import 'session/session_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw first; initialize behind DainBoot, which shows any failure.
  runApp(const DainBoot(init: _start));
}

bool _supabaseReady = false;

Future<Widget> _start() async {
  if (!_supabaseReady) {
    await Supabase.initialize(
      url: DainConfig.supabaseUrl,
      publishableKey: DainConfig.supabaseKey,
    );
    _supabaseReady = true;
  }
  final client = Supabase.instance.client;
  final controller = SessionController(
    auth: SupabaseAuthRepository(client),
    profiles: SupabaseProfileRepository(client),
  );
  unawaited(controller.start());
  return DainApp(
    controller: controller,
    ledgers: SupabaseLedgerRepository(client),
  );
}
