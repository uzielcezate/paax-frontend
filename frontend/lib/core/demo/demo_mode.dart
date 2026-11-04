// lib/core/demo/demo_mode.dart
//
// Portfolio demo mode — OPT-IN entry point, web only.
//
// Demo mode is requested exclusively through the launch URL of the web build:
//   https://paaxmusic.app/?demo=1      (canonical, works with any URL strategy)
//   https://paaxmusic.app/demo         (path form, needs SPA fallback on the host)
//   https://paaxmusic.app/#/demo       (fragment form)
//
// It is NEVER active on mobile (`kIsWeb` guard) and never active without one
// of those markers, so the normal app — AuthGate, login, registration — is the
// default on every platform. Requesting demo mode does not bypass anything by
// itself: `DemoGate` only shows the shell after the backend has minted a valid
// demo session and the Supabase client holds that session.

import 'package:flutter/foundation.dart' show kIsWeb;

class DemoMode {
  DemoMode._();

  /// Pure check used by [isRequested] and by tests.
  static bool isRequestedFor(Uri uri) {
    final q = uri.queryParameters['demo'];
    if (q == '1' || q == 'true') return true;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last == 'demo') return true;
    final frag = uri.fragment.split('?').first;
    if (frag == '/demo' || frag == 'demo') return true;
    return false;
  }

  /// True only for the web build launched with a demo marker.
  static bool get isRequested => kIsWeb && isRequestedFor(Uri.base);
}
