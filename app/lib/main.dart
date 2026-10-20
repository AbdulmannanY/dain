import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/auth_repository.dart';
import 'data/ledger_repository.dart';
import 'data/profile_repository.dart';
import 'session/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: DainConfig.supabaseUrl,
    publishableKey: DainConfig.supabaseKey,
  );
  final client = Supabase.instance.client;
  final controller = SessionController(
    auth: SupabaseAuthRepository(client),
    profiles: SupabaseProfileRepository(client),
  );
  runApp(
    DainApp(controller: controller, ledgers: SupabaseLedgerRepository(client)),
  );
  await controller.start();
}
