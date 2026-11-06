@TestOn('browser')
library;

// Regression test for the Web YouTube player frame (2026-11-06).
//
// youtube_player_iframe_web 3.0.2–3.1.2 hard-coded a `credentialless`
// <iframe> for the player (anonymous, cookie-less context). On
// demo.paaxmusic.app that frame was intermittently rejected by YouTube with
// player error 150 / errorCode "auth", while an otherwise identical frame
// without the attribute played. 3.1.3 makes the attribute configurable and
// defaults it to false; this test pins that behaviour for the code path the
// youtube_player_iframe package actually uses on Web (it passes a plain
// PlatformWebViewControllerCreationParams, which the web implementation
// converts with `fromPlatformWebViewControllerCreationParams`).
//
// Run with: flutter test --platform chrome test/web/

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
// Transitive via youtube_player_iframe; referenced only to exercise the exact
// conversion path the plugin uses in production.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
// ignore: implementation_imports
import 'package:youtube_player_iframe_web/src/web_youtube_player_iframe_controller.dart';

void main() {
  group('Web YouTube player iframe', () {
    test('default creation params do not request a credentialless frame', () {
      final params = WebYoutubePlayerIframeControllerCreationParams();
      final web.HTMLIFrameElement frame = params.ytiFrame.element;

      expect(params.credentialless, isFalse);
      expect(frame.hasAttribute('credentialless'), isFalse,
          reason: 'the player must load in a normal (credentialed) context');
    });

    test('the conversion path used by youtube_player_iframe keeps it off', () {
      // youtube_player_iframe constructs its controller with
      // `const PlatformWebViewControllerCreationParams()`; the web plugin then
      // converts it. This is the production code path.
      final params = WebYoutubePlayerIframeControllerCreationParams
          .fromPlatformWebViewControllerCreationParams(
        const PlatformWebViewControllerCreationParams(),
      );
      final web.HTMLIFrameElement frame = params.ytiFrame.element;

      expect(params.credentialless, isFalse);
      expect(frame.hasAttribute('credentialless'), isFalse);
    });

    test('frame keeps the attributes the engine relies on', () {
      final params = WebYoutubePlayerIframeControllerCreationParams();
      final web.HTMLIFrameElement frame = params.ytiFrame.element;

      expect(frame.id, startsWith('youtube-'));
      expect(frame.allow, 'autoplay;fullscreen');
      expect(frame.style.width, '100%');
      expect(frame.style.height, '100%');
    });

    test('credentialless remains available as an explicit opt-in', () {
      // Documents the knob so a future change is deliberate, not accidental.
      final params =
          WebYoutubePlayerIframeControllerCreationParams(credentialless: true);
      final web.HTMLIFrameElement frame = params.ytiFrame.element;

      expect(params.credentialless, isTrue);
      expect(frame.hasAttribute('credentialless'), isTrue);
    });

    test('srcdoc is applied to the frame (player document path)', () {
      final params = WebYoutubePlayerIframeControllerCreationParams();
      params.ytiFrame.srcdoc = '<!DOCTYPE html><title>t</title>';
      final web.HTMLIFrameElement frame = params.ytiFrame.element;

      expect(frame.srcdoc.toString(), contains('<title>t</title>'));
      expect(frame.hasAttribute('credentialless'), isFalse);
    });
  });
}
