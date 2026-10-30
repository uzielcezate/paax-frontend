// lib/presentation/screens/demo/demo_screens.dart
//
// The three demo-only surfaces. Deliberately minimal and on-brand (PAAX dark
// background, white primary action) — the real app is what the visitor should
// see; these only bracket the session.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class DemoStartingScreen extends StatelessWidget {
  const DemoStartingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Wordmark(),
            SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            ),
            SizedBox(height: 18),
            Text(
              'Starting your demo…',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class DemoEndedScreen extends StatelessWidget {
  const DemoEndedScreen({super.key, required this.onRestart, this.reason});

  final VoidCallback onRestart;
  final String? reason;

  String get _subtitle {
    switch (reason) {
      case 'signed_out':
        return 'You signed out of the demo account.';
      case 'expired':
      default:
        return 'Your 10-minute session is over. Everything you created in it has been cleared.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Wordmark(),
                const SizedBox(height: 32),
                const Text(
                  'Demo Session Ended',
                  key: Key('demo_ended_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 32),
                _PrimaryButton(
                  key: const Key('demo_restart'),
                  label: 'Restart Demo',
                  onPressed: onRestart,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DemoErrorScreen extends StatelessWidget {
  const DemoErrorScreen(
      {super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Wordmark(),
                const SizedBox(height: 32),
                const Text(
                  'The demo could not start',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  key: const Key('demo_error_message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 32),
                _PrimaryButton(
                  key: const Key('demo_retry'),
                  label: 'Try again',
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'PAAX',
      style: TextStyle(
        color: Colors.white,
        fontSize: 30,
        fontWeight: FontWeight.w900,
        letterSpacing: 6,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(
      {super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
