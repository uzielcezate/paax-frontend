// test/unit/player_layout_metrics_test.dart — Visual polish §3 + refinement V2.
//
// The Full Player's control scaling must grow without ever overflowing the
// row horizontally, keep ≥48dp touch targets, and leave a usable artwork
// area on compact and standard phones. V2 asks Play / Prev / Next for 150%
// of their V1 size and the secondary controls for the ratios listed below.

import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/presentation/screens/player_screen.dart'
    show kPlayerHorizontalPadding;
import 'package:beaty/presentation/widgets/player_layout_metrics.dart';

void main() {
  const phones = <String, double>{
    'compact (320)': 320,
    'standard Android (360)': 360,
    'iPhone SE (375)': 375,
    'Pixel (393)': 393,
    'Pixel XL (412)': 412,
    'large (430)': 430,
  };

  test('metrics gutter matches the screen padding', () {
    expect(PlayerControlMetrics.kPlayerGutter, kPlayerHorizontalPadding);
  });

  for (final entry in phones.entries) {
    final content = entry.value - 2 * kPlayerHorizontalPadding;
    final m = PlayerControlMetrics.forWidth(content);

    test('${entry.key}: five controls fit the widened row without overflow',
        () {
      expect(m.rowMinWidth, lessThanOrEqualTo(m.rowWidth + 0.001));
      expect(m.rowWidth, lessThanOrEqualTo(entry.value)); // never off-screen
      expect(m.rowWidth,
          entry.value - 2 * PlayerControlMetrics.kControlsEdgeInset);
    });

    test('${entry.key}: play/prev/next grew vs V1, up to the 1.5× request',
        () {
      expect(m.achievedPrimaryMultiplier, greaterThan(1.0));
      expect(m.achievedPrimaryMultiplier,
          lessThanOrEqualTo(PlayerControlMetrics.kPrimaryBoost));
      expect(m.playFitted, closeTo(m.v1PlayIcon * m.achievedPrimaryMultiplier, 1e-9));
      expect(m.skipIcon, closeTo(m.v1SkipIcon * m.achievedPrimaryMultiplier, 1e-9));
    });

    test('${entry.key}: V3 play glyph is 95% of its fitted box, hit box kept',
        () {
      expect(m.playIcon, closeTo(m.playFitted * 0.95, 1e-9));
      expect(m.playBox, m.playFitted); // touch target not reduced
      expect(m.playIcon, greaterThan(m.v1PlayIcon)); // still larger than V1
    });

    test('${entry.key}: shuffle/repeat keep their V1 size', () {
      expect(m.shuffleIcon, PlayerControlMetrics.baseShuffle * m.secondaryScale);
      expect(m.secondaryScale, inInclusiveRange(1.0, PlayerControlMetrics.maxScale));
    });

    test('${entry.key}: touch targets stay at least 48dp', () {
      expect(m.shuffleBox, greaterThanOrEqualTo(48));
      expect(m.skipBox, greaterThanOrEqualTo(48));
      expect(m.playBox, greaterThanOrEqualTo(48));
      expect(m.rowHeight, greaterThanOrEqualTo(48));
    });

    test('${entry.key}: the row is sized to the play glyph, not its em box',
        () {
      expect(m.rowHeight, lessThan(m.playIcon));
      expect(m.rowHeight, greaterThanOrEqualTo(m.skipBox));
    });
  }

  test('a 393dp phone gets a clearly larger play button than V1', () {
    final m = PlayerControlMetrics.forWidth(393 - 2 * kPlayerHorizontalPadding);
    // Width-limited: 1.5× does not fit; the fitter must land well above 1.2×.
    expect(m.achievedPrimaryMultiplier, greaterThan(1.2));
  });

  group('isolated control ratios (relative to V1)', () {
    test('header icons are 150%', () {
      expect(PlayerControlMetrics.headerChevronIcon, 32 * 1.5);
      expect(PlayerControlMetrics.headerMenuIcon, 26 * 1.5);
    });
    test('like is 80%, add is 65%', () {
      expect(PlayerControlMetrics.likeIcon, 40 * 0.8);
      expect(PlayerControlMetrics.addRing, closeTo(48 * 0.65, 0.5));
      expect(PlayerControlMetrics.addIcon, closeTo(30 * 0.65, 0.5));
    });
    test('cast and queue are 45–50%', () {
      expect(PlayerControlMetrics.castIcon / 36, inInclusiveRange(0.45, 0.50));
      expect(PlayerControlMetrics.queueIcon / 40, inInclusiveRange(0.45, 0.50));
    });
  });

  group('vertical layout', () {
    PlayerVerticalLayout layoutFor(double w, double h,
        {double top = 24, double bottom = 48}) {
      final content = w - 2 * kPlayerHorizontalPadding;
      return PlayerControlMetrics.forWidth(content).verticalLayout(
          safeHeight: h - top - bottom, contentWidth: content);
    }

    test('standard phone: full-width artwork and the lower section lifted',
        () {
      final l = layoutFor(393, 851);
      expect(l.artworkSize, 393 - 2 * kPlayerHorizontalPadding);
      // Most of the slack goes below the controls (lifts Play), the rest
      // between artwork and title.
      expect(l.bottomExtra, greaterThan(l.artworkToInfoExtra));
      expect(l.bottomExtra, greaterThan(40));
      expect(l.artworkToInfoExtra, lessThan(60));
      // V3: slack shares sum to 1 and the controls→lower share keeps the
      // cast/queue row in place while the block above moves up.
      expect(
          PlayerControlMetrics.kBottomSlackShare +
              PlayerControlMetrics.kArtworkToInfoSlackShare +
              PlayerControlMetrics.kControlsToLowerSlackShare,
          closeTo(1.0, 1e-9));
      expect(l.controlsToLowerExtra, closeTo(l.artworkToInfoExtra, 1e-9));
    });

    test('tall phone: no overflow, slack stays bounded', () {
      final l = layoutFor(430, 932);
      expect(l.artworkSize, 430 - 2 * kPlayerHorizontalPadding);
      expect(l.bottomExtra + l.artworkToInfoExtra, lessThan(200));
    });

    test('compact phone (320×568): artwork shrinks instead of overflowing',
        () {
      final content = 320 - 2 * kPlayerHorizontalPadding;
      final m = PlayerControlMetrics.forWidth(content);
      final l = m.verticalLayout(safeHeight: 568 - 24 - 8, contentWidth: content);
      expect(l.artworkSize, greaterThanOrEqualTo(PlayerControlMetrics.minArtwork));
      expect(l.artworkSize, lessThan(content));
      expect(l.artworkSize + m.reservedHeight, lessThanOrEqualTo(568 - 24 - 8));
      expect(l.bottomExtra, 0);
      expect(l.artworkToInfoExtra, 0);
      expect(l.controlsToLowerExtra, 0);
    });

    test('short wide phone (360×640): still fits', () {
      final content = 360 - 2 * kPlayerHorizontalPadding;
      final m = PlayerControlMetrics.forWidth(content);
      final l = m.verticalLayout(safeHeight: 640 - 24 - 48, contentWidth: content);
      expect(l.artworkSize + m.reservedHeight, lessThanOrEqualTo(640 - 24 - 48));
    });

    test('artwork never exceeds its width cap', () {
      final l = layoutFor(600, 2000);
      expect(l.artworkSize, PlayerControlMetrics.maxArtworkWidth);
    });
  });

  test('degenerate widths fall back to 1× rather than throwing', () {
    expect(PlayerControlMetrics.forWidth(double.infinity).secondaryScale, 1.0);
    expect(PlayerControlMetrics.forWidth(0).secondaryScale, 1.0);
    expect(PlayerControlMetrics.forWidth(-5).primaryScale, 1.0);
  });
}
