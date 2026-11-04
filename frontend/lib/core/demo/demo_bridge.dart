// lib/core/demo/demo_bridge.dart
//
// Platform-conditional postMessage bridge to the embedding portfolio page.
export 'demo_bridge_stub.dart'
    if (dart.library.js_interop) 'demo_bridge_web.dart';
