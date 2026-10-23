// test/unit/artist_header_style_test.dart — Visual polish §1–§2.

import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/core/theme/app_colors.dart';
import 'package:beaty/presentation/widgets/artist_header_style.dart';

void main() {
  group('hero gradient', () {
    final g = artistHeroGradient();

    test('ends in the exact page background colour, fully opaque', () {
      expect(g.colors.last, AppColors.background);
      expect(g.colors.last.a, 1.0);
    });

    test('starts fully transparent and keeps the top third clear', () {
      expect(g.colors.first.a, 0.0);
      final clearStops = g.stops!.where((s) => s <= kArtistHeroFadeStart);
      for (var i = 0; i < clearStops.length; i++) {
        expect(g.colors[i].a, 0.0);
      }
    });

    test('every stop is the background colour (no colour shift / band)', () {
      for (final c in g.colors) {
        expect(c.r, AppColors.background.r);
        expect(c.g, AppColors.background.g);
        expect(c.b, AppColors.background.b);
      }
    });

    test('alpha ramps monotonically with no step larger than 0.25', () {
      final alphas = g.colors.map((c) => c.a).toList();
      for (var i = 1; i < alphas.length; i++) {
        expect(alphas[i], greaterThanOrEqualTo(alphas[i - 1]));
        expect(alphas[i] - alphas[i - 1], lessThanOrEqualTo(0.25));
      }
      final stops = g.stops!;
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThan(stops[i - 1]));
      }
      expect(stops.last, 1.0);
    });
  });

  group('header spacing', () {
    test('name block sits lower than the old 24dp inset on every phone', () {
      for (final w in [320.0, 360.0, 390.0, 430.0]) {
        expect(artistHeaderBottomInset(w), lessThan(24));
        expect(artistHeaderBottomInset(w), greaterThanOrEqualTo(8));
      }
    });

    test('followers → controls gap is tighter than the old 16dp', () {
      for (final w in [320.0, 360.0, 390.0, 430.0]) {
        expect(artistHeaderActionsGap(w), lessThan(16));
        expect(artistHeaderActionsGap(w), greaterThanOrEqualTo(6));
      }
    });

    test('spacing is responsive but bounded', () {
      expect(artistHeaderBottomInset(100), 8);
      expect(artistHeaderBottomInset(10000), 12);
      expect(artistHeaderActionsGap(100), 6);
      expect(artistHeaderActionsGap(10000), 8);
    });
  });
}
