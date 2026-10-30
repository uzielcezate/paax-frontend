// lib/data/remote/supabase_demo_session_adapter.dart
//
// The ONLY place demo mode touches the Supabase SDK. Adopting the minted
// session goes through `setSession`, which fires the same `signedIn` event a
// real login does, so AuthController, LibraryController, HomeController etc.
// react exactly as they do for a normal user — nothing is bypassed.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../presentation/state/demo_session_controller.dart';

class SupabaseDemoSessionAdapter implements DemoSessionAdapter {
  SupabaseDemoSessionAdapter([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String demoFlag = 'paax_demo';

  @override
  String? currentAccessToken() => _client.auth.currentSession?.accessToken;

  @override
  bool currentUserIsDemo() {
    final meta = _client.auth.currentUser?.appMetadata;
    return meta != null && meta[demoFlag] == true;
  }

  @override
  Future<void> adoptSession(String refreshToken, String accessToken) async {
    // Both tokens → the SDK validates the access token with GoTrue, stores the
    // session and emits `signedIn`, exactly like a password login. (Refresh
    // token alone would emit `tokenRefreshed`, which AuthController ignores.)
    await _client.auth.setSession(refreshToken, accessToken: accessToken);
  }

  @override
  Future<void> dropLocalSession() async {
    // Local scope: the identity is deleted server-side by paax-api, so a
    // network sign-out would only fail. Still fires `signedOut` locally.
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}
