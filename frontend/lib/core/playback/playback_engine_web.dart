import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'playback_engine.dart';

class PlaybackEngineImpl implements PlaybackEngine {
  late YoutubePlayerController _controller;
  
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _completionController = StreamController<void>.broadcast();
  final _stateController = StreamController<int>.broadcast();
  final _errorController = StreamController<int>.broadcast();
  
  Timer? _positionTimer;
  bool _isDisposed = false;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;
  
  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<void> get completionStream => _completionController.stream;

  @override
  Stream<int> get playerStateStream => _stateController.stream;

  @override
  Stream<int> get errorStream => _errorController.stream;

  static int _stateToInt(PlayerState s) {
    switch (s) {
      case PlayerState.unStarted:
        return -1;
      case PlayerState.ended:
        return 0;
      case PlayerState.playing:
        return 1;
      case PlayerState.paused:
        return 2;
      case PlayerState.buffering:
        return 3;
      case PlayerState.cued:
        return 5;
      default:
        return -99;
    }
  }

  @override
  Future<void> initialize() async {
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
         showControls: false,
         showFullscreenButton: false,
         mute: false,
         loop: false,
      ),
    );
    
    // Listen to iframe events
    _controller.listen((event) {
        if (_isDisposed) return;

        // Raw state + error signals for the play transaction.
        if (!_stateController.isClosed) {
          _stateController.add(_stateToInt(event.playerState));
        }
        if (event.error != YoutubeError.none && !_errorController.isClosed) {
          _errorController.add(event.error.index);
        }

        // Sync Duration
        _durationController.add(event.metaData.duration);

        // Sync Playing State & Timer
        if (event.playerState == PlayerState.playing) {
            _playingController.add(true);
            _startPositionTimer();
        } else if (event.playerState == PlayerState.paused || event.playerState == PlayerState.ended) {
            _playingController.add(false);
            _stopPositionTimer();
            if (event.playerState == PlayerState.ended) {
               _completionController.add(null);
            }
        } else {
           // buffer, etc.
        }
    });
  }

  @override
  void prefetchNext(String videoId) {
    // No-op on web — stream resolution is handled by the YouTube iframe API.
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopPositionTimer();
    _positionController.close();
    _durationController.close();
    _playingController.close();
    _completionController.close();
    _stateController.close();
    _errorController.close();
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        if (_isDisposed) {
           _stopPositionTimer();
           return;
        }
        try {
           final pos = await _controller.currentTime;
           _positionController.add(Duration(milliseconds: (pos * 1000).toInt()));
        } catch (_) {}
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  @override
  Future<void> load(String videoId) async {
    _controller.loadVideoById(videoId: videoId);
  }

  @override
  Future<void> pause() async {
    _controller.pauseVideo();
  }

  @override
  Future<void> play() async {
    _controller.playVideo();
  }

  @override
  Future<void> seek(Duration position) async {
    _controller.seekTo(seconds: position.inSeconds.toDouble(), allowSeekAhead: true);
  }

  @override
  Widget buildPlayerView(BuildContext context) {
    _schedulePointerPassthrough();
    return IgnorePointer(
      child: YoutubePlayer(
         controller: _controller,
         aspectRatio: 16/9,
      ),
    );
  }

  // ── Web hit-testing fix ─────────────────────────────────────────────────────
  // On web the hidden player is a real DOM <iframe> (a platform view) sitting
  // under the top-left 300×300 px of the page. Platform views receive browser
  // pointer events natively, BEFORE Flutter's own hit-testing, so every tap in
  // that square (first Home card, the Search field, "Top Result", artist header)
  // was swallowed by the iframe and never reached a Flutter widget. The player
  // is driven entirely through the IFrame API (controls hidden), so it never
  // needs pointer input: make the iframe (and its slot) transparent to pointer
  // events. Taps then fall through to <flutter-view>, where Flutter handles them.
  // Mobile is untouched (this file is only compiled for web).
  bool _passthroughScheduled = false;

  void _schedulePointerPassthrough() {
    if (_passthroughScheduled) return;
    _passthroughScheduled = true;
    var attempts = 0;
    void attempt() {
      if (_isDisposed) return;
      final applied = _applyPointerPassthrough();
      // The iframe is created lazily after the HtmlElementView mounts; keep
      // trying briefly, and keep re-asserting for a while in case it is
      // re-created.
      if (++attempts < 40) {
        Future<void>.delayed(
            Duration(milliseconds: applied ? 1000 : 250), attempt);
      } else {
        _passthroughScheduled = false; // a later rebuild re-arms the check
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
  }

  /// Returns true when at least one player iframe was found and patched.
  static bool _applyPointerPassthrough() {
    try {
      final view = web.document.querySelector('flutter-view');
      if (view == null) return false;
      // The engine may host the platform view in the light DOM (observed with
      // Flutter 3.41 / CanvasKit) or behind a shadow root; look in both.
      final root = view.shadowRoot;
      const selector = 'iframe[id^="youtube-"]';
      final frames = root != null
          ? root.querySelectorAll(selector)
          : web.document.querySelectorAll(selector);
      var found = false;
      for (var i = 0; i < frames.length; i++) {
        final el = frames.item(i);
        if (el == null) continue;
        (el as web.HTMLElement).style.pointerEvents = 'none';
        found = true;
        // Also the enclosing platform-view slot, so nothing in the chain
        // claims the pointer.
        var parent = el.parentElement;
        while (parent != null && parent != view) {
          if (parent.tagName == 'FLT-PLATFORM-VIEW' ||
              parent.tagName == 'FLT-PLATFORM-VIEW-SLOT') {
            (parent as web.HTMLElement).style.pointerEvents = 'none';
          }
          parent = parent.parentElement;
        }
      }
      return found;
    } catch (_) {
      return false; // best-effort; never break playback over a DOM quirk
    }
  }
}
