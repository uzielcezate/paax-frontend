// lib/data/remote/demo_session_api.dart
//
// Thin client for paax-api's /v2/demo endpoints (see docs/features/demo-mode.md).
// No credentials live here: the backend mints a throwaway identity and returns
// its session tokens; this class just carries them back to the Supabase SDK.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';

class DemoSessionApiException implements Exception {
  DemoSessionApiException(this.statusCode, this.code, this.message);
  final int statusCode;
  final String code;
  final String message;

  bool get isRateLimited => statusCode == 429;
  bool get isDisabled => statusCode == 503;

  @override
  String toString() => 'DemoSessionApiException($statusCode $code: $message)';
}

/// What the backend returns for a freshly minted session.
class DemoSessionGrant {
  const DemoSessionGrant({
    required this.sessionId,
    required this.accessToken,
    required this.refreshToken,
    required this.durationSeconds,
    required this.expiresAt,
  });

  final String sessionId;
  final String accessToken;
  final String refreshToken;
  final int durationSeconds;
  final DateTime expiresAt;

  factory DemoSessionGrant.fromJson(Map<String, dynamic> json) {
    final session = (json['session'] as Map?)?.cast<String, dynamic>() ?? {};
    final auth = (json['auth'] as Map?)?.cast<String, dynamic>() ?? {};
    return DemoSessionGrant(
      sessionId: (session['id'] ?? '') as String,
      accessToken: (auth['access_token'] ?? '') as String,
      refreshToken: (auth['refresh_token'] ?? '') as String,
      durationSeconds: (session['duration_seconds'] as num?)?.toInt() ?? 600,
      expiresAt: DateTime.tryParse('${session['expires_at']}')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

class DemoSessionStatus {
  const DemoSessionStatus(
      {required this.active, required this.remainingSeconds});
  final bool active;
  final int remainingSeconds;

  factory DemoSessionStatus.fromJson(Map<String, dynamic> json) {
    final session = (json['session'] as Map?)?.cast<String, dynamic>() ?? {};
    return DemoSessionStatus(
      active: session['active'] == true,
      remainingSeconds: (session['remaining_seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class DemoSessionApi {
  DemoSessionApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 20);

  Uri _uri(String path) => Uri.parse('$_baseUrl/v2/demo$path');

  Future<DemoSessionGrant> create({String client = 'portfolio'}) async {
    final res = await _client
        .post(_uri('/sessions'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'client': client}))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 201) throw _asError(res.statusCode, body);
    return DemoSessionGrant.fromJson(body);
  }

  Future<DemoSessionStatus> status(String accessToken) async {
    final res = await _client.get(_uri('/sessions/me'),
        headers: {'Authorization': 'Bearer $accessToken'}).timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) throw _asError(res.statusCode, body);
    return DemoSessionStatus.fromJson(body);
  }

  Future<void> end(String accessToken) async {
    final res = await _client.post(_uri('/sessions/end'),
        headers: {'Authorization': 'Bearer $accessToken'}).timeout(_timeout);
    if (res.statusCode != 200) throw _asError(res.statusCode, _decode(res));
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return const {};
    try {
      final v = jsonDecode(res.body);
      return v is Map ? v.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  DemoSessionApiException _asError(int status, Map<String, dynamic> body) {
    final err = (body['error'] as Map?)?.cast<String, dynamic>();
    return DemoSessionApiException(
      status,
      (err?['code'] ?? 'DEMO_ERROR') as String,
      (err?['message'] ?? body['detail'] ?? 'Demo request failed') as String,
    );
  }
}
