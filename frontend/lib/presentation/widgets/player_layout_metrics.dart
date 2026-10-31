import 'dart:math' as math;

/// Sizing contract for the Full Player, kept as a pure value object so the
/// control scaling and the vertical budget are unit-testable.
///
/// Two generations of sizes live here:
///
/// * **v1 (visual polish, PR #98)** scaled the five main controls from their
///   24 / 40 / 76 bases toward 2× as a function of the row width
///   ([secondaryScale]). Shuffle / Repeat keep exactly that size.
/// * **v2 (visual refinement)** asks Play / Prev / Next for 150% of their v1
///   size ([kPrimaryBoost]). The three cannot always fit next to two 48dp
///   Shuffle / Repeat hit boxes, so the row is allowed to extend into the
///   player's horizontal gutters (down to [kControlsEdgeInset] from the screen
///   edge) and the boost is then reduced to the largest value that fits
///   ([primaryScale], reported through [achievedPrimaryMultiplier]).
///
/// Isolated controls (like, add, cast, queue, header icons) are fixed sizes.
class PlayerControlMetrics {
  const PlayerControlMetrics._({
    required this.secondaryScale,
    required this.primaryScale,
    required this.rowWidth,
  });

  /// v1 multiplier (1.0 … 2.0): still applied to Shuffle / Repeat.
  final double secondaryScale;

  /// Extra multiplier applied on top of [secondaryScale] to Play / Prev /
  /// Next. Requested [kPrimaryBoost]; smaller only when the row cannot fit.
  final double primaryScale;

  /// Width the controls row may use (content width plus the reclaimed gutter).
  final double rowWidth;

  static const double baseShuffle = 24;
  static const double baseSkip = 40;
  static const double basePlay = 76;
  static const double maxScale = 2.0;

  /// Requested growth of Play / Prev / Next relative to their v1 size.
  static const double kPrimaryBoost = 1.5;

  /// Lowest boost the fitter may fall back to on absurdly narrow widths.
  static const double _minPrimaryBoost = 0.5;

  /// Share of the content width the v1 icons may occupy at most.
  static const double kControlsRowFill = 0.85;

  /// Horizontal padding of the Full Player content column.
  static const double kPlayerGutter = 24;

  /// The controls row keeps at least this much distance from the screen
  /// edge; the rest of the gutter is reclaimed for the larger primary icons.
  static const double kControlsEdgeInset = 12;

  /// Minimum touch target for the small controls.
  static const double minTouchTarget = 48;

  /// Vertical share of a Material play / pause glyph inside its em box
  /// (`play_arrow_rounded` / `pause_rounded` span y 5→19 of 24 ≈ 0.58). The
  /// row is sized to the glyph, not the em box, so the empty quarter above and
  /// below the triangle no longer pushes the row apart.
  static const double kPlayGlyphHeightRatio = 0.62;

  /// V3: the fitted Play / Pause glyph is drawn at 95% of its em box while
  /// the hit box keeps the fitted width (touch target unchanged).
  static const double kPlayVisualScale = 0.95;

  static const double _baseIconsSum = baseShuffle * 2 + baseSkip * 2 + basePlay;

  /// [contentWidth] is the width of the player's content column (screen width
  /// minus `2 × kPlayerGutter`).
  factory PlayerControlMetrics.forWidth(double contentWidth) {
    if (!contentWidth.isFinite || contentWidth <= 0) {
      return const PlayerControlMetrics._(
          secondaryScale: 1.0, primaryScale: 1.0, rowWidth: 0);
    }
    final s1 = _legacyScale(contentWidth);
    final rowWidth = contentWidth + 2 * (kPlayerGutter - kControlsEdgeInset);

    PlayerControlMetrics at(double f) => PlayerControlMetrics._(
        secondaryScale: s1, primaryScale: f, rowWidth: rowWidth);

    var hi = kPrimaryBoost;
    if (at(hi).rowMinWidth <= rowWidth) return at(hi);
    var lo = _minPrimaryBoost;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (at(mid).rowMinWidth <= rowWidth) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return at(lo);
  }

  /// v1 scale: fill share capped at 2×, then bisected so the zero-gap row of
  /// 48dp-minimum hit boxes fits the content width.
  static double _legacyScale(double contentWidth) {
    final target = ((contentWidth * kControlsRowFill) / _baseIconsSum)
        .clamp(1.0, maxScale);
    double rowAt(double s) =>
        math.max(minTouchTarget, baseShuffle * s) * 2 +
        math.max(minTouchTarget, baseSkip * s) * 2 +
        basePlay * s;
    if (rowAt(target) <= contentWidth) return target;
    var lo = 1.0;
    var hi = target;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (rowAt(mid) <= contentWidth) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Multiplier actually achieved for Play / Prev / Next relative to the v1
  /// (pre-refinement) size: 1.5 when the row fits, less on narrow phones.
  double get achievedPrimaryMultiplier => primaryScale;

  double get shuffleIcon => baseShuffle * secondaryScale;
  double get skipIcon => baseSkip * secondaryScale * primaryScale;

  /// Em box of Play / Pause as fitted into the row (also its hit width).
  double get playFitted => basePlay * secondaryScale * primaryScale;

  /// Visual size of the Play / Pause glyph ([kPlayVisualScale] × fitted).
  double get playIcon => playFitted * kPlayVisualScale;

  /// v1 sizes, kept for before/after reporting and tests.
  double get v1SkipIcon => baseSkip * secondaryScale;
  double get v1PlayIcon => basePlay * secondaryScale;

  /// Hit box of each control: at least [minTouchTarget], never below the icon.
  double get shuffleBox => math.max(minTouchTarget, shuffleIcon);
  double get skipBox => math.max(minTouchTarget, skipIcon);

  /// Width of the Play hit box (the fitted em box, not the 95% glyph).
  double get playBox => playFitted;

  /// Total width the five controls need with zero gaps.
  double get rowMinWidth => shuffleBox * 2 + skipBox * 2 + playBox;

  /// Height of the controls row: the visible play glyph (its em box is
  /// allowed to overflow vertically), but never below the neighbours' hit
  /// boxes.
  double get rowHeight => math.max(
      playIcon * kPlayGlyphHeightRatio, math.max(skipBox, shuffleBox));

  // ── Isolated controls ──
  // v2 ratios are relative to the v1 sizes noted on each line.
  static const double headerChevronIcon = 48; // v1 32 → 150%
  static const double headerMenuIcon = 39; // v1 26 → 150%
  static const double likeIcon = 32; // v1 40 → 80%
  static const double addRing = 31; // v1 48 → 65%
  static const double addIcon = 20; // v1 30 → 65%
  static const double addRingBorder = 1.5; // v1 2
  static const double castIcon = 17; // v1 36 → 47%
  static const double queueIcon = 19; // v1 40 → 47.5%

  // ── Vertical rhythm (song mode, lyrics collapsed) ──
  static const double headerHeight = 52;

  /// Header → artwork.
  static const double headerGap = 8;

  /// Artwork → title block (before any distributed slack). V3: 14 → 10.
  static const double artworkToInfoGap = 10;
  static const double infoToProgressGap = 6;
  static const double progressToControlsGap = 0;

  /// Controls → cast/queue row (before any distributed slack). V3: 0 → 4.
  static const double controlsToLowerGap = 4;
  static const double bottomGap = 4;
  static const double infoRowHeight = 64; // title + artist + 48dp buttons
  static const double progressHeight = 40;
  static const double lowerRowHeight = 48;

  /// Shares of the leftover height: below the lower actions (lifts the whole
  /// lower section instead of pinning it to the bottom edge), between the
  /// artwork and the title, and between the controls and the cast/queue row
  /// (V3: the title/progress/controls block moved up without moving cast and
  /// queue). They sum to 1.
  static const double kBottomSlackShare = 0.7;
  static const double kArtworkToInfoSlackShare = 0.15;
  static const double kControlsToLowerSlackShare = 0.15;

  /// Height of the compact synced-lyrics viewport inside the artwork slot:
  /// ≈3 lyric entries (56dp each) plus part of a neighbour.
  static const double compactLyricsHeight = 200;

  /// Smallest artwork before the column is allowed to overflow.
  static const double minArtwork = 160;
  static const double maxArtworkWidth = 440;

  /// Vertical space the column needs besides the artwork and the distributed
  /// slack.
  double get reservedHeight =>
      headerHeight +
      headerGap +
      artworkToInfoGap +
      infoRowHeight +
      infoToProgressGap +
      progressHeight +
      progressToControlsGap +
      rowHeight +
      controlsToLowerGap +
      lowerRowHeight +
      bottomGap;

  /// Song-mode vertical layout for a safe-area height of [safeHeight] and a
  /// content column of [contentWidth].
  PlayerVerticalLayout verticalLayout({
    required double safeHeight,
    required double contentWidth,
  }) {
    final free = safeHeight - reservedHeight;
    final byWidth = math.min(contentWidth, maxArtworkWidth);
    final artwork =
        free.clamp(minArtwork, math.max(minArtwork, byWidth)).toDouble();
    final slack = math.max(0.0, free - artwork);
    return PlayerVerticalLayout(
      artworkSize: artwork,
      artworkToInfoExtra: slack * kArtworkToInfoSlackShare,
      controlsToLowerExtra: slack * kControlsToLowerSlackShare,
      bottomExtra: slack * kBottomSlackShare,
    );
  }
}

/// Result of [PlayerControlMetrics.verticalLayout].
class PlayerVerticalLayout {
  const PlayerVerticalLayout({
    required this.artworkSize,
    required this.artworkToInfoExtra,
    required this.controlsToLowerExtra,
    required this.bottomExtra,
  });

  final double artworkSize;

  /// Added to [PlayerControlMetrics.artworkToInfoGap].
  final double artworkToInfoExtra;

  /// Added to [PlayerControlMetrics.controlsToLowerGap].
  final double controlsToLowerExtra;

  /// Added to [PlayerControlMetrics.bottomGap].
  final double bottomExtra;
}
