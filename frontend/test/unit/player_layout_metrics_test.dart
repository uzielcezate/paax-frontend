// test/unit/player_layout_metrics_test.dart — Visual polish §3.
//
// The Full Player's control scaling must grow toward 2× without ever
// overflowing the row horizontally, keep ≥48dp touch targets, and leave a
// usable artwork area on compact and standard phones.

import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/presentation/screens/player_screen.dart'
    show kPlayerHorizontalPadding;
import 'package:beaty/presentation/widgets/player_layout_metrics.dart';

void main() {
  const phones = <String, double>{
    'compact (320)': 320,
    'iPhone SE (375)': 375,
    'standard Android (360)': 360,
    'Pixel (412)': 412,
    'large (430)': 430,
  };

  for (final entry in phones.entries) {
    final content = entry.value - 2 * kPlayerHorizontalPadding;
    final m = PlayerControlMetrics.forWidth(content);

    test('${entry.key}: five controls fit without overflow', () {
      expect(m.rowMinWidth, lessThanOrEqualTo(content));
    });

    test('${entry.key}: controls are larger than before, capped at 2×', () {
      expect(m.scale, greaterThan(1.0));
      expect(m.scale, lessThanOrEqualTo(PlayerControlMetrics.maxScale));
      expect(m.playIcon, greaterThan(PlayerControlMetrics.basePlay));
    });

    test('${entry.key}: touch targets stay at least 48dp', () {
      expect(m.shuffleBox, greaterThanOrEqualTo(48));
      expect(m.skipBox, greaterThanOrEqualTo(48));
      expect(m.playBox, greaterThanOrEqualTo(48));
    });
  }

  test('compact phone (320×568) still leaves room for the artwork', () {
    const width = 320.0, height = 568.0, topInset = 24.0, bottomInset = 8.0;
    final m =
        PlayerControlMetrics.forWidth(width - 2 * kPlayerHorizontalPadding);
    final available = height - topInset - bottomInset - m.reservedHeight;
    // Mirrors the screen: artwork is clamped to 85% of the free height.
    expect(available * 0.85, greaterThan(150));
  });

  test('standard phone (390×844) can show a ≥240dp artwork', () {
    const width = 390.0, height = 844.0, topInset = 47.0, bottomInset = 34.0;
    final m =
        PlayerControlMetrics.forWidth(width - 2 * kPlayerHorizontalPadding);
    final available = height - topInset - bottomInset - m.reservedHeight;
    expect(available * 0.85, greaterThanOrEqualTo(240));
  });

  test('isolated controls are about twice their previous size', () {
    expect(PlayerControlMetrics.likeIcon, closeTo(26 * 2, 14));
    expect(PlayerControlMetrics.castIcon, closeTo(18 * 2, 2));
    expect(PlayerControlMetrics.queueIcon, closeTo(20 * 2, 2));
    expect(PlayerControlMetrics.addRing, closeTo(28 * 2, 10));
  });

  test('degenerate widths fall back to 1× rather than throwing', () {
    expect(PlayerControlMetrics.forWidth(double.infinity).scale, 1.0);
    expect(PlayerControlMetrics.forWidth(0).scale, 1.0);
    expect(PlayerControlMetrics.forWidth(-5).scale, 1.0);
  });
}
