import 'dart:math' as math;

/// Sizing contract for the Full Player, kept as a pure value object so the
/// control scaling and the vertical budget are unit-testable.
///
/// The visual target is ~2× the pre-polish icon sizes (shuffle/repeat 24,
/// prev/next 40, play 76). The five main controls share one row, so the
/// scale is derived from the available content width and capped at 2×: the
/// icons may take at most [kControlsRowFill] of the row, which guarantees
/// the row never overflows horizontally (gaps are distributed by
/// `MainAxisAlignment.spaceBetween`). Isolated controls (like, add, queue,
/// cast) are not width-constrained and use their own fixed 2× sizes.
class PlayerControlMetrics {
  const PlayerControlMetrics._(this.scale);

  /// Multiplier applied to the five main playback icons (1.0 … 2.0).
  final double scale;

  static const double baseShuffle = 24;
  static const double baseSkip = 40;
  static const double basePlay = 76;
  static const double maxScale = 2.0;

  /// Share of the content width the five icons may occupy at most.
  static const double kControlsRowFill = 0.85;

  /// Minimum touch target for the small controls.
  static const double minTouchTarget = 48;

  static const double _baseIconsSum = baseShuffle * 2 + baseSkip * 2 + basePlay;

  /// [contentWidth] is the width available to the controls row (screen width
  /// minus the player's horizontal padding).
  factory PlayerControlMetrics.forWidth(double contentWidth) {
    if (!contentWidth.isFinite || contentWidth <= 0) {
      return const PlayerControlMetrics._(1.0);
    }
    final target = ((contentWidth * kControlsRowFill) / _baseIconsSum)
        .clamp(1.0, maxScale);
    // The 48dp minimum hit boxes do not shrink with the scale, so on compact
    // phones the fill share alone can still overflow. Bisect for the largest
    // scale (≤ target) whose zero-gap row fits; `lo` is always feasible.
    var lo = 1.0;
    var hi = target;
    if (PlayerControlMetrics._(hi).rowMinWidth <= contentWidth) {
      return PlayerControlMetrics._(hi);
    }
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (PlayerControlMetrics._(mid).rowMinWidth <= contentWidth) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return PlayerControlMetrics._(lo);
  }

  double get shuffleIcon => baseShuffle * scale;
  double get skipIcon => baseSkip * scale;
  double get playIcon => basePlay * scale;

  /// Hit box of each control: at least [minTouchTarget], never below the icon.
  double get shuffleBox => math.max(minTouchTarget, shuffleIcon);
  double get skipBox => math.max(minTouchTarget, skipIcon);
  double get playBox => playIcon;

  /// Total width the five controls need with zero gaps.
  double get rowMinWidth => shuffleBox * 2 + skipBox * 2 + playBox;

  /// Height of the controls row (the play glyph is the tallest member).
  double get rowHeight => playBox;

  // ── Isolated controls (≈2× their previous sizes) ──
  static const double likeIcon = 40; // was 26
  static const double addRing = 48; // was 28
  static const double addIcon = 30; // was 18
  static const double castIcon = 36; // was 18
  static const double queueIcon = 40; // was 20

  // ── Vertical rhythm (song mode, lyrics collapsed) ──
  static const double headerHeight = 52;
  static const double headerGap = 4;
  static const double infoToProgressGap = 10;
  static const double progressToControlsGap = 2;
  static const double controlsToLowerGap = 0;
  static const double bottomGap = 4;
  static const double infoRowHeight = 64; // title + artist + 48dp buttons
  static const double progressHeight = 40;
  static const double lowerRowHeight = 48;

  /// Vertical space reserved below the artwork area; the artwork is sized to
  /// what remains. Replaces the old hard-coded 340.
  double get reservedHeight =>
      headerHeight +
      headerGap +
      infoRowHeight +
      infoToProgressGap +
      progressHeight +
      progressToControlsGap +
      rowHeight +
      controlsToLowerGap +
      lowerRowHeight +
      bottomGap;
}
