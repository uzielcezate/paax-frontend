import 'dart:ui' show FlutterView, Size;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Phone / tablet split used for the orientation lock. Matches the Material
/// convention (and `Responsive.mobileBreakpoint`): a device whose *shortest*
/// logical side is under 600dp is a phone.
const double kPortraitLockShortestSideDp = 600.0;

/// Whether a device with [logicalSize] (any orientation) should be locked to
/// portrait. Uses the shortest side, which is rotation-invariant, so the
/// answer cannot flip after a rotation the way a width-only check would.
bool shouldLockPortrait(Size logicalSize) =>
    logicalSize.shortestSide < kPortraitLockShortestSideDp;

/// Logical size of [view] in device-independent pixels.
Size logicalSizeOf(FlutterView view) =>
    view.physicalSize / view.devicePixelRatio;

/// Applies PAAX's orientation policy: smartphones are portrait-up only;
/// tablets and larger screens keep every orientation (their responsive
/// layouts already handle landscape).
///
/// Portrait-down is deliberately excluded: Android only honours it with
/// `sensorPortrait`, which flips the UI upside-down while the system bars stay
/// put on several OEM skins — not worth it for a music player.
///
/// The preference is set on the Activity and survives backgrounding, system
/// overlays and configuration changes, so calling this once at startup is
/// sufficient. Safe to call again (idempotent).
Future<void> applyOrientationPolicy() async {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return; // headless / test binding: nothing to lock
  final size = logicalSizeOf(views.first);
  if (size.isEmpty) return;
  if (shouldLockPortrait(size)) {
    await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp]);
  } else {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}
