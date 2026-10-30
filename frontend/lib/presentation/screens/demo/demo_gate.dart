// lib/presentation/screens/demo/demo_gate.dart
//
// Demo entry point (web, `?demo=1`). Wraps — never replaces — the existing
// AuthGate: once a demo session is active the normal startup machine routes
// the minted identity to the real shell exactly like any signed-in user.
//
//   starting → DemoStartingScreen
//   active   → AuthGate (real app)
//   ended    → DemoEndedScreen ("Demo Session Ended" + Restart Demo)
//   error    → DemoErrorScreen (Retry)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/startup/startup_state.dart';
import '../../state/auth_controller.dart';
import '../../state/demo_session_controller.dart';
import '../auth/auth_gate.dart';
import 'demo_screens.dart';

class DemoGate extends StatefulWidget {
  const DemoGate({super.key});

  @override
  State<DemoGate> createState() => _DemoGateState();
}

class _DemoGateState extends State<DemoGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: discarded_futures
      context.read<DemoSessionController>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<DemoSessionController>();
    final authPhase =
        context.select<AuthController, StartupPhase>((a) => a.phase);

    // The visitor used the real Log out: treat it as the end of the demo (the
    // controller double-checks the Supabase session is really gone).
    if (demo.isActive && authPhase == StartupPhase.unauthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // ignore: discarded_futures
        context.read<DemoSessionController>().onSignedOutExternally();
      });
    }

    switch (demo.phase) {
      case DemoPhase.idle:
      case DemoPhase.starting:
      case DemoPhase.ending:
        return const DemoStartingScreen();
      case DemoPhase.active:
        return const AuthGate();
      case DemoPhase.ended:
        return DemoEndedScreen(
          reason: demo.endReason,
          onRestart: () => context.read<DemoSessionController>().restart(),
        );
      case DemoPhase.error:
        return DemoErrorScreen(
          message: demo.errorMessage ?? 'Something went wrong.',
          onRetry: () => context.read<DemoSessionController>().restart(),
        );
    }
  }
}
