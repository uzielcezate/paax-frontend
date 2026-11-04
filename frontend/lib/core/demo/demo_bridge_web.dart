// Web: notify the embedding page (the portfolio) about demo lifecycle events
// via `window.parent.postMessage`. The payload carries ONLY lifecycle state
// (phase, remaining seconds, expiry) — never tokens — so a wildcard target
// origin is safe. When the app is not embedded, `parent == window` and the
// message is harmlessly delivered to itself.

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void postDemoMessage(Map<String, Object?> message) {
  try {
    final parent = web.window.parent;
    if (parent == null) return;
    // A JSON string keeps the contract trivially portable for the portfolio.
    parent.postMessage(jsonEncode(message).toJS, '*'.toJS);
  } catch (_) {
    // Best-effort only.
  }
}
