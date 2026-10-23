import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Layout + paint constants for the Artist Profile hero header. Kept as pure
/// functions so the spacing contract and the gradient are unit-testable.

/// Gap between the bottom of the hero image and the name/followers block.
/// Scales with width (the hero is a square of the screen width) and is kept
/// small so the followers pill sits close to the Shuffle / Play / Follow row.
double artistHeaderBottomInset(double screenWidth) =>
    (screenWidth * 0.028).clamp(8.0, 12.0);

/// Space between the hero (followers pill) and the action buttons row.
double artistHeaderActionsGap(double screenWidth) =>
    (screenWidth * 0.02).clamp(6.0, 8.0);

/// Fraction of the hero height where the fade starts (face stays clear).
const double kArtistHeroFadeStart = 0.32;

/// Vertical gradient laid over the hero image so it dissolves into the exact
/// page background with no identifiable boundary: fully transparent for the
/// top third, then an eased (smoothstep-like) ramp to the opaque background
/// colour at the very bottom. Every stop is the page background at a
/// different alpha, so there is no colour shift (the old `0x99121212` middle
/// stop was a different grey than `AppColors.background` and read as a band).
LinearGradient artistHeroGradient({Color background = AppColors.background}) {
  const stops = <double>[
    0.0,
    kArtistHeroFadeStart,
    0.42,
    0.52,
    0.62,
    0.72,
    0.82,
    0.91,
    1.0,
  ];
  // Smoothstep over [fadeStart, 1.0].
  double alphaAt(double t) {
    if (t <= kArtistHeroFadeStart) return 0.0;
    final x = ((t - kArtistHeroFadeStart) / (1.0 - kArtistHeroFadeStart))
        .clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      for (final s in stops) background.withValues(alpha: alphaAt(s)),
    ],
    stops: stops,
  );
}
