// test/unit/demo_session_controller_test.dart
//
// Demo lifecycle with a fake backend and a fake Supabase adapter:
//   start → active (server-seeded countdown) → expiry stops playback, ends the
//   session server-side, drops the local session, clears local state → ended;
//   restart mints a NEW identity; reload resumes the SAME remaining time; a
//   server "inactive" answer ends the session even if the local clock disagrees.

// ignore_for_file: depend_on_referenced_packages — fake_async ships with flutter_test.
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:beaty/data/remote/demo_session_api.dart';
import 'package:beaty/presentation/state/demo_session_controller.dart';

class FakeBackend {
  int created = 0;
  final List<String> ended = [];
  int statusCalls = 0;
  bool serverActive = true;
  int serverRemaining = 600;
  int createStatus = 201;
  int durationSeconds = 600;

  http.Client client() => MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/v2/demo/sessions') && req.method == 'POST') {
          if (createStatus != 201) {
            return http.Response(
                jsonEncode({
                  'error': {'code': 'DEMO_RATE_LIMITED', 'message': 'slow down'}
                }),
                createStatus);
          }
          created++;
          return http.Response(
              jsonEncode({
                'session': {
                  'id': 'u$created',
                  'duration_seconds': durationSeconds,
                  'expires_at': '2026-10-30T12:10:00Z',
                },
                'auth': {
                  'access_token': 'at$created',
                  'refresh_token': 'rt$created'
                },
                'user': {'id': 'u$created', 'username': 'demo_$created'},
              }),
              201);
        }
        if (path.endsWith('/v2/demo/sessions/me')) {
          statusCalls++;
          return http.Response(
              jsonEncode({
                'session': {
                  'active': serverActive,
                  'remaining_seconds': serverRemaining
                }
              }),
              200);
        }
        if (path.endsWith('/v2/demo/sessions/end')) {
          ended.add(req.headers['Authorization'] ?? '');
          return http.Response(
              jsonEncode({
                'session': {'ended': true}
              }),
              200);
        }
        return http.Response('nope', 404);
      });
}

class FakeAdapter implements DemoSessionAdapter {
  String? token;
  bool isDemo = false;
  final List<String> adopted = [];
  int drops = 0;

  @override
  String? currentAccessToken() => token;
  @override
  bool currentUserIsDemo() => isDemo;
  @override
  Future<void> adoptSession(String refreshToken, String accessToken) async {
    adopted.add(refreshToken);
    assert(accessToken.isNotEmpty);
    token = 'at${adopted.length}';
    isDemo = true;
  }

  @override
  Future<void> dropLocalSession() async {
    drops++;
    token = null;
    isDemo = false;
  }
}

void main() {
  late FakeBackend backend;
  late FakeAdapter adapter;
  late int pauses;
  late int clears;
  late List<Map<String, Object?>> posted;

  DemoSessionController make(FakeAsync fa,
      {Duration revalidate = const Duration(seconds: 60)}) {
    return DemoSessionController(
      api:
          DemoSessionApi(client: backend.client(), baseUrl: 'https://api.test'),
      adapter: adapter,
      pausePlayback: () async => pauses++,
      clearLocalState: () async => clears++,
      now: () => fa.getClock(DateTime.utc(2026, 10, 30, 12)).now(),
      revalidateEvery: revalidate,
      postMessage: posted.add,
    );
  }

  setUp(() {
    backend = FakeBackend();
    adapter = FakeAdapter();
    pauses = 0;
    clears = 0;
    posted = [];
  });

  test(
      'start mints a session, adopts it and counts down from the server duration',
      () {
    fakeAsync((fa) {
      final c = make(fa);
      c.bootstrap();
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.active);
      expect(backend.created, 1);
      expect(adapter.adopted, ['rt1']);
      expect(c.remainingSeconds, 600);
      expect(posted.first['event'], 'started');

      fa.elapse(const Duration(seconds: 30));
      expect(c.remainingSeconds, 570);
      expect(posted.last['event'], 'tick');
      c.dispose();
    });
  });

  test(
      'expiry: pauses playback, ends server-side, drops session, clears state → ended',
      () {
    fakeAsync((fa) {
      final c = make(fa, revalidate: const Duration(hours: 1));
      c.bootstrap();
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 601));
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.ended);
      expect(c.endReason, 'expired');
      expect(pauses, 1);
      expect(backend.ended, ['Bearer at1']);
      expect(adapter.drops, 1);
      expect(clears, 1);
      expect(c.remainingSeconds, 0);
      expect(posted.last['event'], 'ended');
      c.dispose();
    });
  });

  test('restart after expiry mints a NEW identity with a fresh 600 s', () {
    fakeAsync((fa) {
      final c = make(fa, revalidate: const Duration(hours: 1));
      c.bootstrap();
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 601));
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.ended);

      c.restart();
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.active);
      expect(backend.created, 2);
      expect(adapter.adopted, ['rt1', 'rt2']);
      expect(c.sessionId, 'u2');
      expect(c.remainingSeconds, 600);
      c.dispose();
    });
  });

  test(
      'reload resumes the SAME session with the server remaining time (no fresh 10 min)',
      () {
    fakeAsync((fa) {
      adapter.token = 'at-existing';
      adapter.isDemo = true;
      backend.serverRemaining = 123;
      final c = make(fa);
      c.bootstrap();
      fa.flushMicrotasks();
      expect(backend.created, 0); // no new identity
      expect(c.phase, DemoPhase.active);
      expect(c.remainingSeconds, 123);
      c.dispose();
    });
  });

  test('reload of an expired session ends it instead of restarting', () {
    fakeAsync((fa) {
      adapter.token = 'at-existing';
      adapter.isDemo = true;
      backend.serverActive = false;
      backend.serverRemaining = 0;
      final c = make(fa);
      c.bootstrap();
      fa.flushMicrotasks();
      expect(backend.created, 0);
      expect(c.phase, DemoPhase.ended);
      expect(adapter.drops, 1);
      c.dispose();
    });
  });

  test('periodic server revalidation wins over the local clock', () {
    fakeAsync((fa) {
      final c = make(fa, revalidate: const Duration(seconds: 60));
      c.bootstrap();
      fa.flushMicrotasks();
      backend.serverActive = false; // server says: over
      fa.elapse(const Duration(seconds: 61));
      fa.flushMicrotasks();
      expect(backend.statusCalls, 1);
      expect(c.phase, DemoPhase.ended);
      expect(c.endReason, 'expired');
      c.dispose();
    });
  });

  test(
      'a real sign-out while active ends the demo (only when the session is really gone)',
      () {
    fakeAsync((fa) {
      final c = make(fa, revalidate: const Duration(hours: 1));
      c.bootstrap();
      fa.flushMicrotasks();
      // Spurious call while the session still exists → ignored.
      c.onSignedOutExternally();
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.active);
      // Real sign-out: adapter has no session anymore.
      adapter.token = null;
      c.onSignedOutExternally();
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.ended);
      expect(c.endReason, 'signed_out');
      c.dispose();
    });
  });

  test('rate limiting surfaces a friendly error and Retry mints again', () {
    fakeAsync((fa) {
      backend.createStatus = 429;
      final c = make(fa);
      c.bootstrap();
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.error);
      expect(c.errorMessage, contains('Too many demo sessions'));
      backend.createStatus = 201;
      c.restart();
      fa.flushMicrotasks();
      expect(c.phase, DemoPhase.active);
      c.dispose();
    });
  });
}
