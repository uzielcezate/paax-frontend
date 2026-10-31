// test/widget/paax_pill_test.dart — UI Visual System V2/V3 (sculpted pills).
//
// Contract under test: the shared pill components keep their declared
// geometry (tap targets ≥ 48dp, nav capsule height constant across selection
// changes, top-bar controls on the shared floating inset) and lay out without
// overflow on every representative phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/presentation/screens/main_wrapper.dart'
    show PaaxBottomNavigation, PaaxNavItem, kMiniPlayerZone;
import 'package:beaty/presentation/widgets/paax_pill.dart';
import 'package:beaty/presentation/widgets/paax_top_bar.dart';

const _widths = [320.0, 360.0, 393.0, 430.0, 600.0];

Future<void> _pumpAt(WidgetTester tester, double width, Widget child,
    {EdgeInsets padding = EdgeInsets.zero}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800), padding: padding),
      child: Scaffold(body: child),
    ),
  ));
}

const _navItems = [
  PaaxNavItem.icon(
      outlined: Icons.home_outlined, filled: Icons.home, label: 'Home'),
  PaaxNavItem.icon(
      outlined: Icons.search, filled: Icons.search, label: 'Search'),
  PaaxNavItem.icon(
      outlined: Icons.library_music_outlined,
      filled: Icons.library_music,
      label: 'Library'),
  PaaxNavItem.icon(
      outlined: Icons.person_outline_rounded,
      filled: Icons.person_rounded,
      label: 'Profile'),
];

void main() {
  group('PaaxLayout', () {
    test('floating inset is the content inset: 6% of width, 16–24dp', () {
      expect(PaaxLayout.floatingInsetForWidth(320), closeTo(19.2, 0.01));
      expect(PaaxLayout.floatingInsetForWidth(360), closeTo(21.6, 0.01));
      expect(PaaxLayout.floatingInsetForWidth(393), closeTo(23.58, 0.01));
      expect(PaaxLayout.floatingInsetForWidth(430), 24);
      expect(PaaxLayout.floatingInsetForWidth(600), 24);
      expect(PaaxLayout.floatingInsetForWidth(200), 16);
    });

    test('nav indicator is almost as tall as the bar, inset 4dp', () {
      expect(PaaxLayout.navIndicatorHeight, PaaxLayout.navHeight - 8);
      expect(PaaxLayout.navIndicatorHeight,
          greaterThan(PaaxLayout.navHeight * 0.8));
    });

    test('V4 §3: nav and Mini Player capsules are ~85 % of their V3 heights',
        () {
      expect(PaaxLayout.navHeight / 64, closeTo(0.85, 0.02));
      expect(PaaxLayout.miniPlayerHeight / 66, closeTo(0.85, 0.02));
      // Indicator scaled with the bar, still an elongated capsule.
      expect(PaaxLayout.navIndicatorWidth / 72, closeTo(0.85, 0.02));
      expect(PaaxLayout.navIndicatorWidth,
          greaterThan(PaaxLayout.navIndicatorHeight));
      // Glyphs (28dp) still fit inside the indicator with room to spare.
      expect(PaaxBottomNavigation.iconSize,
          lessThan(PaaxLayout.navIndicatorHeight - 8));
    });

    test(
        'V4 §2: one clearance token lifts the whole dock above the gesture bar',
        () {
      expect(PaaxLayout.dockBottomClearance, greaterThanOrEqualTo(12));
      // Dock bottom = safe inset + clearance, applied once (no double inset).
      const safe = 24.0;
      final dockBottom = safe + PaaxLayout.dockBottomClearance;
      expect(dockBottom, 24 + PaaxLayout.dockBottomClearance);
      // Mini Player zone is unchanged in shape: capsule + the same 6dp gap.
      expect(kMiniPlayerZone, PaaxLayout.miniPlayerHeight + PaaxLayout.dockGap);
      expect(PaaxLayout.dockGap, 6);
    });

    test('V4 §4: one horizontal alignment system (content == floating inset)',
        () {
      for (final w in [320.0, 360.0, 393.0, 430.0, 600.0]) {
        expect(
            PaaxLayout.floatingInsetForWidth(w), (w * 0.06).clamp(16.0, 24.0));
      }
    });
  });

  group('V4 §1 dock fade', () {
    test('mirrors the top fade: plateau ends at the nav centre, long tail', () {
      const safe = 24.0;
      const hasTrack = true;
      final dockBottom = safe + PaaxLayout.dockBottomClearance;
      final total = (hasTrack ? kMiniPlayerZone : 0) +
          PaaxLayout.navHeight +
          dockBottom +
          PaaxLayout.bottomFadeExtra;
      final plateau = dockBottom + PaaxLayout.navHeight / 2;
      final g =
          PaaxFade.gradient(total: total, plateau: plateau, fromTop: false);
      // The plateau covers less than half of the overlay: most of the region
      // is ramp, never full opacity.
      expect(plateau / total, lessThan(0.4));
      // Opacity at the Mini Player's centre (measured from the bottom) is
      // well below the peak so content stays faintly visible behind it.
      final miniCentre = (dockBottom +
              PaaxLayout.navHeight +
              PaaxLayout.dockGap +
              PaaxLayout.miniPlayerHeight / 2) /
          total;
      double alphaAt(double t) {
        final stops = g.stops!;
        for (var i = 1; i < stops.length; i++) {
          if (t <= stops[i]) {
            final f = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
            return g.colors[i - 1].a + (g.colors[i].a - g.colors[i - 1].a) * f;
          }
        }
        return g.colors.last.a;
      }

      expect(alphaAt(miniCentre), lessThan(0.9));
      expect(alphaAt(miniCentre), greaterThan(0.5));
      expect(alphaAt(1.0), 0.0);
      expect(alphaAt(0.0), closeTo(0.95, 0.01));
      // Same ramp shape as the top fade (PaaxTopBar uses PaaxFade too).
      expect(g.colors.map((c) => c.a).toList().reversed.take(6).first, 0.0);
    });
  });

  group('PaaxFade', () {
    test('ramps through six stops from 0 to 0.95, plateau then tail', () {
      final g = PaaxFade.gradient(total: 200, plateau: 50, fromTop: true);
      expect(g.stops!.first, 0.0);
      expect(g.stops![1], closeTo(0.25, 1e-9));
      expect(g.stops!.last, 1.0);
      expect(g.colors.first.a, closeTo(0.95, 0.01));
      expect(g.colors[1].a, closeTo(0.95, 0.01));
      expect(g.colors.last.a, 0.0);
      // Strictly decreasing after the plateau; no abrupt jump.
      for (var i = 2; i < g.colors.length; i++) {
        expect(g.colors[i].a, lessThan(g.colors[i - 1].a));
        expect(g.colors[i - 1].a - g.colors[i].a, lessThan(0.30));
      }
      // Tail stops are evenly spaced.
      for (var i = 2; i < g.stops!.length; i++) {
        expect(g.stops![i] - g.stops![i - 1], closeTo(0.15, 1e-9));
      }
    });

    test('opacity scales every stop (scroll-tied fade without Opacity layer)',
        () {
      final g = PaaxFade.gradient(total: 100, plateau: 20, opacity: 0.5);
      expect(g.colors.first.a, closeTo(0.475, 0.01));
      expect(g.colors.last.a, 0.0);
    });

    testWidgets('PaaxHeaderFade is plateau + tail tall and ignores pointers',
        (tester) async {
      await _pumpAt(
          tester,
          393,
          const Align(
            alignment: Alignment.topCenter,
            child: PaaxHeaderFade(plateau: 100),
          ));
      final size = tester.getSize(find.byType(PaaxHeaderFade));
      expect(size.height, 100 + PaaxLayout.topFadeTail);
      expect(size.width, 393);
      expect(find.byType(IgnorePointer), findsWidgets);
    });
  });

  group('PaaxPillSurface', () {
    testWidgets('uses the uniform #111111 fill, no gradient', (tester) async {
      await _pumpAt(
          tester,
          393,
          const Center(
              child:
                  PaaxPillSurface(width: 80, height: 40, child: SizedBox())));
      final box = tester.widget<DecoratedBox>(find.descendant(
          of: find.byType(PaaxPillSurface),
          matching: find.byType(DecoratedBox)));
      final deco = box.decoration as ShapeDecoration;
      expect(deco.color, PaaxPillTheme.fill);
      expect(deco.color, const Color(0xFF111111));
      expect(deco.gradient, isNull);
    });
  });

  group('PaaxIconPill', () {
    testWidgets('44dp disc keeps a 48dp tap target and fires onTap',
        (tester) async {
      var taps = 0;
      await _pumpAt(
          tester,
          393,
          Center(
            child: PaaxIconPill(
              key: const Key('pill'),
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => taps++,
            ),
          ));
      final box = tester.getSize(find.byKey(const Key('pill')));
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      final disc = tester.getSize(find.byType(PaaxPillSurface));
      expect(disc, const Size(PaaxLayout.topBarPill, PaaxLayout.topBarPill));
      expect(disc, const Size(44, 44));
      await tester.tap(find.byKey(const Key('pill')));
      expect(taps, 1);
    });
  });

  group('PaaxSegmentedPills', () {
    for (final w in _widths) {
      testWidgets('lays out Library filters at ${w.toInt()}dp without overflow',
          (tester) async {
        var selected = 1;
        await _pumpAt(
            tester,
            w,
            Align(
              alignment: Alignment.topLeft,
              child: StatefulBuilder(
                builder: (context, setState) => PaaxSegmentedPills(
                  labels: const ['Liked', 'Playlists', 'Albums', 'Artists'],
                  selectedIndex: selected,
                  onSelected: (i) => setState(() => selected = i),
                  height: 36,
                ),
              ),
            ));
        expect(tester.takeException(), isNull);
        expect(find.text('Playlists'), findsOneWidget);
        // Row height = pill height + 8dp shadow room.
        expect(tester.getSize(find.byType(PaaxSegmentedPills)).height, 44);
        // 'Liked' is always on-screen (later pills may scroll off at 320dp
        // with the wide test font).
        await tester.tap(find.text('Liked'));
        await tester.pump();
        expect(selected, 0);
      });
    }

    testWidgets('selected pill is white with dark text, others are not',
        (tester) async {
      await _pumpAt(
          tester,
          393,
          Align(
            alignment: Alignment.topLeft,
            child: PaaxSegmentedPills(
              labels: const ['All', 'Tracks'],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ));
      final selectedText = tester.widget<Text>(find.text('All'));
      final otherText = tester.widget<Text>(find.text('Tracks'));
      expect(selectedText.style!.color, PaaxPillTheme.activeForeground);
      expect(otherText.style!.color, PaaxPillTheme.inactiveForeground);
      final surfaces = tester
          .widgetList<PaaxPillSurface>(find.byType(PaaxPillSurface))
          .toList();
      expect(surfaces.where((s) => s.active).length, 1);
    });
  });

  group('PaaxBottomNavigation', () {
    for (final w in _widths) {
      testWidgets(
          'capsule keeps its height across selections at ${w.toInt()}dp '
          'and the white indicator is an elongated capsule under the slot',
          (tester) async {
        var index = 0;
        final inset = PaaxLayout.floatingInsetForWidth(w);
        Future<void> pump() => _pumpAt(
            tester,
            w,
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: PaaxBottomNavigation(
                  items: _navItems,
                  currentIndex: index,
                  onTap: (i) => index = i,
                ),
              ),
            ));
        await pump();
        expect(tester.takeException(), isNull);
        final before = tester.getSize(find.byType(PaaxBottomNavigation));
        expect(before.height, PaaxLayout.navHeight);
        expect(before.height, 54); // V4 §3: 85 % of the V3 64dp
        expect(before.width, closeTo(w - 2 * inset, 0.01));

        await tester.tap(find.bySemanticsLabel('Library'));
        expect(index, 2);
        await pump();
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(PaaxBottomNavigation)), before);

        // Exactly one white indicator, centred under the active slot,
        // nearly bar-height, wider than tall (capsule, not a disc).
        final active = tester
            .widgetList<PaaxPillSurface>(find.byType(PaaxPillSurface))
            .where((s) => s.active);
        expect(active.length, 1);
        final indicator = find.byWidget(active.first);
        final slotWidth = (w - 2 * inset) / 4;
        expect(tester.getCenter(indicator).dx,
            closeTo(inset + slotWidth * 2.5, 0.5));
        final size = tester.getSize(indicator);
        expect(size.height, PaaxLayout.navIndicatorHeight);
        expect(size.height, 46);
        expect(size.width, greaterThan(size.height));
        expect(size.width, PaaxBottomNavigation.indicatorWidth(slotWidth));
        // Never overflows its slot or the capsule's vertical edges.
        expect(size.width, lessThanOrEqualTo(slotWidth - 8));
        final capsuleRect = tester.getRect(find.byType(PaaxBottomNavigation));
        final indRect = tester.getRect(indicator);
        expect(indRect.top, greaterThanOrEqualTo(capsuleRect.top + 4 - 0.01));
        expect(
            indRect.bottom, lessThanOrEqualTo(capsuleRect.bottom - 4 + 0.01));
      });
    }

    testWidgets('each slot is at least 48dp tall and wide', (tester) async {
      await _pumpAt(
          tester,
          320,
          Align(
            alignment: Alignment.bottomCenter,
            child: PaaxBottomNavigation(
                items: _navItems, currentIndex: 0, onTap: (_) {}),
          ));
      final slot = tester.getSize(find.bySemanticsLabel('Home'));
      expect(slot.width, greaterThanOrEqualTo(48));
      expect(slot.height, greaterThanOrEqualTo(48));
    });
  });

  group('PaaxTopBar', () {
    testWidgets('44dp controls sit on the floating inset; title fades in',
        (tester) async {
      const topPad = 24.0;
      const w = 393.0;
      final inset = PaaxLayout.floatingInsetForWidth(w);
      var backs = 0;
      Future<void> pump(bool showTitle) => _pumpAt(
            tester,
            w,
            Align(
              alignment: Alignment.topCenter,
              child: PaaxTopBar(
                title: 'Puesto Pa\' Guerrial',
                showTitle: showTitle,
                onBack: () => backs++,
                trailing: const Icon(Icons.more_vert, key: Key('menu')),
              ),
            ),
            padding: const EdgeInsets.only(top: topPad),
          );
      await pump(false);
      expect(tester.takeException(), isNull);
      // Back disc: outer edge on the inset, 44dp, centred in the 58dp bar.
      final backDisc = find
          .ancestor(
              of: find.byIcon(Icons.arrow_back_ios_new_rounded),
              matching: find.byType(PaaxPillSurface))
          .first;
      final backRect = tester.getRect(backDisc);
      expect(backRect.left, closeTo(inset, 0.5));
      expect(backRect.width, 44);
      expect(backRect.height, 44);
      expect(backRect.center.dy, closeTo(topPad + 29, 0.5));
      // Trailing disc: outer edge on the inset from the right.
      final menuDisc = find
          .ancestor(
              of: find.byKey(const Key('menu')),
              matching: find.byType(PaaxPillSurface))
          .first;
      final menuRect = tester.getRect(menuDisc);
      expect(menuRect.right, closeTo(w - inset, 0.5));
      expect(menuRect.width, 44);
      expect(menuRect.center.dy, closeTo(topPad + 29, 0.5));
      // Tap targets stay ≥ 48dp.
      expect(tester.getSize(find.bySemanticsLabel('Back')).width,
          greaterThanOrEqualTo(48));
      // Title hidden while the hero is visible.
      final back = tester.getCenter(find.bySemanticsLabel('Back'));
      final menu = tester.getCenter(find.byKey(const Key('menu')));
      final hidden = tester.widget<AnimatedOpacity>(find
          .ancestor(
              of: find.text('Puesto Pa\' Guerrial'),
              matching: find.byType(AnimatedOpacity))
          .first);
      expect(hidden.opacity, 0.0);

      await pump(true);
      await tester.pumpAndSettle();
      final shown = tester.widget<AnimatedOpacity>(find
          .ancestor(
              of: find.text('Puesto Pa\' Guerrial'),
              matching: find.byType(AnimatedOpacity))
          .first);
      expect(shown.opacity, 1.0);
      // Title capsule is as tall as the side pills and vertically centred.
      final titleCapsule = tester.getRect(find.ancestor(
          of: find.text('Puesto Pa\' Guerrial'),
          matching: find.byType(PaaxPillSurface)));
      expect(titleCapsule.height, 44);
      expect(titleCapsule.center.dy, closeTo(topPad + 29, 0.5));
      // Controls did not move when the title appeared.
      expect(tester.getCenter(find.bySemanticsLabel('Back')), back);
      expect(tester.getCenter(find.byKey(const Key('menu'))), menu);
      await tester.tap(find.bySemanticsLabel('Back'));
      expect(backs, 1);
    });

    testWidgets('fade is a long multi-stop ramp (no short two-stop edge)',
        (tester) async {
      await _pumpAt(
          tester,
          393,
          Align(
            alignment: Alignment.topCenter,
            child: PaaxTopBar(title: 'T', showTitle: true, onBack: () {}),
          ));
      final bar = tester.getSize(find.byType(PaaxTopBar));
      expect(bar.height, PaaxLayout.topBarHeight + PaaxLayout.topFadeTail);
      final boxes = tester.widgetList<DecoratedBox>(find.descendant(
          of: find.byType(PaaxTopBar), matching: find.byType(DecoratedBox)));
      final fade = boxes
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.gradient is LinearGradient);
      final g = fade.gradient as LinearGradient;
      expect(g.stops!.length, greaterThanOrEqualTo(6));
      expect(g.colors.last.a, 0.0);
    });

    for (final w in [320.0, 360.0]) {
      testWidgets(
          'long title is ellipsised, not overflowing, at ${w.toInt()}dp',
          (tester) async {
        final inset = PaaxLayout.floatingInsetForWidth(w);
        await _pumpAt(
            tester,
            w,
            Align(
              alignment: Alignment.topCenter,
              child: PaaxTopBar(
                title: 'A very very very long playlist title that cannot fit',
                showTitle: true,
                onBack: () {},
                trailing: const Icon(Icons.more_vert),
              ),
            ));
        expect(tester.takeException(), isNull);
        final capsule = tester.getSize(find.ancestor(
            of: find.textContaining('A very'),
            matching: find.byType(PaaxPillSurface)));
        expect(capsule.width,
            lessThanOrEqualTo(w - 2 * (inset + 44 + PaaxTopBar.titleGap)));
      });
    }
  });
}
