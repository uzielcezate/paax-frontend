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
