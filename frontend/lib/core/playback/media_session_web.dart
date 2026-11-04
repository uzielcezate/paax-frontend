// ============================================================================
// Media Session — Web
// ============================================================================
// Selected by the conditional import in `playback_controller.dart` when
// `dart.library.html` is available. The previous generation of this file
// (a `dart:js` eval-based bridge to `navigator.mediaSession`) was commented
// out wholesale, which left the web build with NO definitions for the four
// functions the controller calls — so `flutter build web` failed to compile
// (`updateMediaSessionDuration`, `updateMediaSessionPlaybackState` and
// `setMediaSession` undefined). See docs/AI_NOTES.md.
//
// On web there is no Foreground Service and no `PaaxAudioHandler`; the
// YouTube IFrame itself already integrates with the browser's media controls.
// These are therefore intentional, documented no-ops with the SAME signatures
// as `media_session_stub.dart`, so the controller compiles on every platform
// and mobile behaviour is untouched.
//
// DESIGN DECISION (owner, 2026-11-03) — THIS IS THE FINAL BEHAVIOUR, NOT A
// TEMPORARY WORKAROUND. Do not "fix" it later:
//   * PAAX Web must NOT override the browser's media metadata for the YouTube
//     IFrame. Browser/OS controls showing YouTube's own metadata (for example
//     "Skrillex - Topic") is accepted and expected.
//   * Do NOT reactivate the old `dart:js` eval bridge and do NOT set
//     `navigator.mediaSession.metadata` / action handlers from Dart on web.
//   * Custom Media Session metadata (title, artist, artwork, controls) is a
//     MOBILE feature only: Android/iOS go through `media_session_stub.dart`
//     → `PaaxAudioHandler` (audio_service) and are unaffected by this file.
//   * Keep the four functions below as no-ops with these exact signatures so
//     `playback_controller.dart` compiles unchanged on every platform.
// ============================================================================

import '../../domain/entities/track.dart';

void setMediaSession({
  required Track track,
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrevious,
}) {
  // No OS media session to drive on web (the IFrame owns it).
}

void updateMediaSessionPlaybackState({
  required bool isPlaying,
  Duration position = Duration.zero,
}) {}

void updateMediaSessionDuration(Duration duration) {}

void clearMediaSession() {}
