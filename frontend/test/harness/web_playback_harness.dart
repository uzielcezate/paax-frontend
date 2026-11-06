// Web playback harness (test tooling only, never shipped).
//
// Builds a tiny Flutter Web page around the REAL web playback engine
// (`core/playback/playback_engine_web.dart` via `getPlaybackEngine()`), mounted
// exactly like `HiddenVideoPlayer` does (300x300 box inside a Stack), so the
// engine's YouTube iframe, state/error streams and pointer pass-through can be
// exercised in a real Chrome against a given build without an authenticated
// PAAX session.
//
// Build:  flutter build web --release -t test/harness/web_playback_harness.dart -o build/harness
// Serve:  any static server (e.g. the Pages-like server used for the demo)
// Drive:  window.postMessage(JSON.stringify({cmd:'load', id:'<videoId>'}), '*')
//         cmds: load {id}, play, pause, seek {seconds}
// Read:   window.__paaxHarness  (JSON string: state, lastError, errors[],
//         position, duration, playing, loads[])
//
// The harness never touches the production app code paths other than
// constructing the engine; it adds nothing to the app bundle.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'package:beaty/core/playback/playback_engine.dart';
import 'package:beaty/core/playback/playback_factory.dart';

void main() {
  runApp(const _HarnessApp());
}

class _HarnessApp extends StatefulWidget {
  const _HarnessApp();

  @override
  State<_HarnessApp> createState() => _HarnessAppState();
}

class _HarnessAppState extends State<_HarnessApp> {
  late final PlaybackEngine _engine;
  final List<StreamSubscription<dynamic>> _subs = [];

  int _state = -99;
  int? _lastError;
  final List<Map<String, Object?>> _errors = [];
  final List<Map<String, Object?>> _loads = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _ready = false;
  String _currentId = '';

  @override
  void initState() {
    super.initState();
    _engine = getPlaybackEngine();
    _engine.initialize().then((_) {
      setState(() => _ready = true);
      _publish();
    });
    _subs.add(_engine.playerStateStream.listen((s) {
      setState(() => _state = s);
      _publish();
    }));
    _subs.add(_engine.errorStream.listen((e) {
      setState(() {
        _lastError = e;
        _errors.add({'code': e, 'id': _currentId, 't': _now()});
      });
      _publish();
    }));
    _subs.add(_engine.positionStream.listen((p) {
      _position = p;
      _publish();
    }));
    _subs.add(_engine.durationStream.listen((d) {
      _duration = d;
      _publish();
    }));
    _subs.add(_engine.playingStream.listen((p) {
      setState(() => _playing = p);
      _publish();
    }));
    web.window.onMessage.listen(_onMessage);
    _publish();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  void _onMessage(web.MessageEvent event) {
    final raw = event.data;
    if (raw == null || !raw.typeofEquals('string')) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode((raw as JSString).toDart);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }
    final cmd = msg['cmd'];
    if (cmd is! String) return;
    switch (cmd) {
      case 'load':
        final id = msg['id'];
        if (id is String && id.isNotEmpty) _load(id);
      case 'play':
        _engine.play();
      case 'pause':
        _engine.pause();
      case 'seek':
        final s = msg['seconds'];
        if (s is num) _engine.seek(Duration(seconds: s.toInt()));
    }
  }

  Future<void> _load(String id) async {
    setState(() {
      _currentId = id;
      _lastError = null;
      _loads.add({'id': id, 't': _now()});
    });
    _publish();
    await _engine.load(id);
  }

  void _publish() {
    final snapshot = <String, Object?>{
      'ready': _ready,
      'currentId': _currentId,
      'state': _state,
      'lastError': _lastError,
      'errors': _errors,
      'loads': _loads,
      'position': _position.inMilliseconds / 1000.0,
      'duration': _duration.inMilliseconds / 1000.0,
      'playing': _playing,
      'updated': _now(),
    };
    web.window.setProperty('__paaxHarness'.toJS, jsonEncode(snapshot).toJS);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Same mounting as presentation/widgets/hidden_video_player.dart.
            SizedBox(
              width: 300,
              height: 300,
              child: _engine.buildPlayerView(context),
            ),
            // Content drawn over the player, like the app's IndexedStack.
            Positioned.fill(
              child: Container(
                color: const Color(0xCC000000),
                padding: const EdgeInsets.all(16),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PAAX web playback harness'),
                      Text('ready=$_ready  id=$_currentId'),
                      Text('state=$_state  playing=$_playing  '
                          'lastError=${_lastError ?? "-"}'),
                      Text('position=${_position.inSeconds}s / '
                          '${_duration.inSeconds}s'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton(
                            key: const Key('btn-play'),
                            onPressed: _engine.play,
                            child: const Text('Play'),
                          ),
                          ElevatedButton(
                            key: const Key('btn-pause'),
                            onPressed: _engine.pause,
                            child: const Text('Pause'),
                          ),
                          ElevatedButton(
                            key: const Key('btn-seek'),
                            onPressed: () =>
                                _engine.seek(const Duration(seconds: 60)),
                            child: const Text('Seek 60s'),
                          ),
                          // Pointer pass-through probe: this button sits inside
                          // the top-left 300x300 square covered by the iframe.
                          ElevatedButton(
                            key: const Key('btn-probe'),
                            onPressed: () {
                              web.window.setProperty(
                                  '__paaxProbeClicks'.toJS,
                                  ((web.window
                                              .getProperty<JSNumber?>(
                                                  '__paaxProbeClicks'.toJS)
                                              ?.toDartInt ??
                                          0) +
                                      1)
                                      .toJS);
                            },
                            child: const Text('Probe'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
