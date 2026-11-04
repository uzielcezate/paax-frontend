// lib/presentation/state/demo_session_controller.dart
//
// Portfolio demo session lifecycle (web only; inert unless `DemoMode.isRequested`).
//
//   idle ──start()──▶ starting ──grant+adopt──▶ active ──(timer / server / sign-out)──▶ ending ──▶ ended
//                        │                                                                     │
//                        └──────────────────────── error ◀───────────────────────────────────┘
//                                                   ▲
//                                        restart() from ended/error → starting
//
// Server authority: the countdown is seeded from the backend's
// `remaining_seconds` / `duration_seconds` (never from the browser clock vs. an
// absolute timestamp, so clock skew cannot extend a session) and re-validated
// against `GET /v2/demo/sessions/me` on every page load and every minute. The
// database additionally rejects the identity after expiry (see migration
// 20261030000000_demo_sessions.sql). Closing and reopening the portfolio modal
// therefore resumes the SAME session with its remaining time — it never grants
// a fresh ten minutes.
//
// This controller does not touch AuthController, the player, or any existing
// screen: it adopts/drops the Supabase session through the SDK (which fires the
// same `signedIn` / `signedOut` events a real login produces) and asks the
// PlaybackController to pause through an injected callback.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/demo/demo_bridge.dart' as bridge;
import '../../data/remote/demo_session_api.dart';

enum DemoPhase { idle, starting, active, ending, ended, error }

/// How the Supabase session is adopted / inspected / dropped. Abstracted so the
/// controller is unit-testable without `supabase_flutter`.
abstract class DemoSessionAdapter {
  /// Access token of the current Supabase session, if any.
  String? currentAccessToken();

  /// True when the current Supabase user carries `app_metadata.paax_demo`.
  bool currentUserIsDemo();

  /// Installs the demo identity's session. MUST pass both tokens: the
  /// Supabase SDK emits `signedIn` only when the access token is supplied;
  /// with a refresh token alone it performs a refresh and emits
  /// `tokenRefreshed`, which the existing AuthController deliberately ignores
  /// (it never re-resolves the profile on a refresh) — the shell would then
  /// stay on Welcome.
  Future<void> adoptSession(String refreshToken, String accessToken);

  /// Drops the local session WITHOUT a network call (the identity is already
  /// being deleted server-side). Fires `signedOut`.
  Future<void> dropLocalSession();
}

class DemoSessionController extends ChangeNotifier {
  DemoSessionController({
    required DemoSessionApi api,
    required DemoSessionAdapter adapter,
    required Future<void> Function() pausePlayback,
    required Future<void> Function() clearLocalState,
    DateTime Function()? now,
    Duration tick = const Duration(seconds: 1),
    Duration revalidateEvery = const Duration(seconds: 60),
    void Function(Map<String, Object?> message)? postMessage,
  })  : _api = api,
        _adapter = adapter,
        _pausePlayback = pausePlayback,
        _clearLocalState = clearLocalState,
        _now = now ?? DateTime.now,
        _tick = tick,
        _revalidateEvery = revalidateEvery,
        _post = postMessage ?? bridge.postDemoMessage;

  final DemoSessionApi _api;
  final DemoSessionAdapter _adapter;
  final Future<void> Function() _pausePlayback;
  final Future<void> Function() _clearLocalState;
  final DateTime Function() _now;
  final Duration _tick;
  final Duration _revalidateEvery;
  final void Function(Map<String, Object?>) _post;

  DemoPhase _phase = DemoPhase.idle;
  DateTime? _expiresAt;
  String? _sessionId;
  String? _errorMessage;
  String? _endReason;
  Timer? _timer;
  int _sinceRevalidate = 0;
  bool _disposed = false;
  bool _bootstrapped = false;

  DemoPhase get phase => _phase;
  String? get sessionId => _sessionId;
  String? get errorMessage => _errorMessage;
  String? get endReason => _endReason;
  DateTime? get expiresAt => _expiresAt;
  bool get isActive => _phase == DemoPhase.active;

  /// Whole seconds left; 0 when not active.
  int get remainingSeconds {
    final e = _expiresAt;
    if (!isActive || e == null) return 0;
    final s = e.difference(_now()).inSeconds;
    return s < 0 ? 0 : s;
  }

  // ── lifecycle ─────────────────────────────────────────────────────────────

  /// Called once by DemoGate. Resumes an existing demo session (server-checked)
  /// or starts a new one. Idempotent.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final token = _adapter.currentAccessToken();
    if (token != null && _adapter.currentUserIsDemo()) {
      _setPhase(DemoPhase.starting);
      try {
        final status = await _api.status(token);
        if (_disposed) return;
        if (status.active && status.remainingSeconds > 0) {
          _arm(status.remainingSeconds);
          return;
        }
        // Expired while the tab was closed: enforce, do not restart silently.
        await _finish('expired', token: token, callEnd: false);
        return;
      } on DemoSessionApiException catch (e) {
        if (_disposed) return;
        if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404) {
          await _finish('expired', token: token, callEnd: false);
          return;
        }
        _fail('Could not verify the demo session. ${e.message}');
        return;
      } catch (_) {
        if (_disposed) return;
        _fail('Could not reach the demo service.');
        return;
      }
    }
    await start();
  }

  Future<void> start() async {
    if (_phase == DemoPhase.starting || _phase == DemoPhase.active) return;
    _errorMessage = null;
    _endReason = null;
    _setPhase(DemoPhase.starting);
    try {
      final grant = await _api.create();
      if (_disposed) return;
      if (grant.refreshToken.isEmpty || grant.accessToken.isEmpty) {
        _fail('The demo service returned an incomplete session.');
        return;
      }
      await _adapter.adoptSession(grant.refreshToken, grant.accessToken);
      if (_disposed) return;
      _sessionId = grant.sessionId;
      _arm(grant.durationSeconds);
    } on DemoSessionApiException catch (e) {
      if (_disposed) return;
      if (e.isRateLimited) {
        _fail(
            'Too many demo sessions from this network. Please try again in a few minutes.');
      } else if (e.isDisabled) {
        _fail('The demo is temporarily unavailable.');
      } else {
        _fail('Could not start the demo. ${e.message}');
      }
    } catch (_) {
      if (_disposed) return;
      _fail('Could not reach the demo service.');
    }
  }

  /// "Restart Demo": a brand-new identity and a fresh ten minutes.
  Future<void> restart() async {
    if (_phase == DemoPhase.starting || _phase == DemoPhase.active) return;
    await start();
  }

  /// Ends the session now (timer hit zero, user signed out, or explicit stop).
  Future<void> end({String reason = 'ended'}) async {
    if (_phase == DemoPhase.ending || _phase == DemoPhase.ended) return;
    await _finish(reason, token: _adapter.currentAccessToken(), callEnd: true);
  }

  /// Called by DemoGate when AuthController reports `unauthenticated` while a
  /// demo was active (e.g. the visitor tapped Log out in Profile).
  Future<void> onSignedOutExternally() async {
    if (_phase != DemoPhase.active) return;
    // AuthController reports `unauthenticated` for a moment between adopting
    // the session and its `signedIn` event; only a genuinely missing Supabase
    // session means the visitor really signed out.
    if (_adapter.currentAccessToken() != null) return;
    await _finish('signed_out', token: null, callEnd: false);
  }

  // ── internals ─────────────────────────────────────────────────────────────

  void _arm(int seconds) {
    _expiresAt = _now().add(Duration(seconds: seconds));
    _sinceRevalidate = 0;
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _onTick());
    _setPhase(DemoPhase.active);
    _post({
      'type': 'paax-demo',
      'event': 'started',
      'remainingSeconds': seconds,
      'expiresAt': _expiresAt!.toUtc().toIso8601String(),
    });
  }

  Future<void> _onTick() async {
    if (_disposed || _phase != DemoPhase.active) return;
    final remaining = remainingSeconds;
    _sinceRevalidate += _tick.inSeconds;
    notifyListeners();
    _post(
        {'type': 'paax-demo', 'event': 'tick', 'remainingSeconds': remaining});
    if (remaining <= 0) {
      await _finish('expired',
          token: _adapter.currentAccessToken(), callEnd: true);
      return;
    }
    if (_sinceRevalidate >= _revalidateEvery.inSeconds) {
      _sinceRevalidate = 0;
      await _revalidate();
    }
  }

  /// Server re-check: the database, not this timer, is the authority.
  Future<void> _revalidate() async {
    final token = _adapter.currentAccessToken();
    if (token == null) return;
    try {
      final status = await _api.status(token);
      if (_disposed || _phase != DemoPhase.active) return;
      if (!status.active) {
        await _finish('expired', token: token, callEnd: false);
        return;
      }
      // Re-seed from the server's remaining time (tolerates clock drift).
      _expiresAt = _now().add(Duration(seconds: status.remainingSeconds));
    } on DemoSessionApiException catch (e) {
      if (_disposed || _phase != DemoPhase.active) return;
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _finish('expired', token: token, callEnd: false);
      }
      // Transient server errors: keep the local countdown running.
    } catch (_) {
      // Network blip: keep the local countdown running.
    }
  }

  Future<void> _finish(String reason,
      {String? token, required bool callEnd}) async {
    _timer?.cancel();
    _timer = null;
    _endReason = reason;
    _setPhase(DemoPhase.ending);
    try {
      await _pausePlayback();
    } catch (_) {}
    if (callEnd && token != null) {
      try {
        await _api.end(token);
      } catch (_) {
        // The server sweeper deletes the identity regardless.
      }
    }
    try {
      await _adapter.dropLocalSession();
    } catch (_) {}
    try {
      await _clearLocalState();
    } catch (_) {}
    if (_disposed) return;
    _expiresAt = null;
    _setPhase(DemoPhase.ended);
    _post({'type': 'paax-demo', 'event': 'ended', 'reason': reason});
  }

  void _fail(String message) {
    _timer?.cancel();
    _timer = null;
    _errorMessage = message;
    _setPhase(DemoPhase.error);
    _post({'type': 'paax-demo', 'event': 'error', 'message': message});
  }

  void _setPhase(DemoPhase p) {
    if (_disposed) return;
    _phase = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
