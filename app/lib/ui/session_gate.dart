import 'package:flutter/material.dart';

import '../session/session_controller.dart';
import 'screens.dart';

/// Shows the screen for the controller's current stage.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => switch (controller.stage) {
        SessionStage.starting => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        SessionStage.enterPhone => PhoneScreen(controller: controller),
        SessionStage.enterCode => CodeScreen(controller: controller),
        SessionStage.needsProfile => ProfileScreen(controller: controller),
        SessionStage.failed => FailedScreen(controller: controller),
        SessionStage.ready => HomeScreen(controller: controller),
      },
    );
  }
}
