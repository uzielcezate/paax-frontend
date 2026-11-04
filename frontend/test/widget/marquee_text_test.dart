// test/widget/marquee_text_test.dart — Visual polish §4–§6.
//
// Contract of the constraint-aware MarqueeText:
// - text that fits never animates and never shows an edge fade;
// - overflowing text is stationary (offset 0) until the cycle starts; its
//   right edge always carries a subtle fade (so a clipped title never reads
//   as complete), the left edge fades only while actually moving, and the
//   offset returns to an exact 0 at the end of each cycle (no overshoot /
//   snapback);
// - a width change re-evaluates overflow: when the text now fits the marquee
//   stops at offset 0 with a single copy; when it overflows again it restarts;
// - a text change resets the animation state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/presentation/widgets/marquee_text.dart';

const _style = TextStyle(fontSize: 20, fontFamily: 'Roboto');
const _short = 'Hi';
// The test font renders every glyph 1em wide: 26 chars × 20px = 520px, so this
// overflows a 120px host and fits in a 600px one.
const _long = 'A long title that overflows';

Widget _host(
  String text, {
  required double width,
  MarqueeController? controller,
  Widget? prefix,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: MarqueeText(
            text: text,
            style: _style,
            controller: controller,
            prefix: prefix,
            pauseDuration: const Duration(milliseconds: 200),
            velocity: 400,
          ),
        ),
      ),
    ),
  );
}

/// Transform widgets that belong to a MarqueeText (MaterialApp has its own).
Finder get _marqueeTransform => find.descendant(
      of: find.byType(MarqueeText),
      matching: find.byType(Transform),
    );

Finder get _marqueeMask => find.descendant(
      of: find.byType(MarqueeText),
      matching: find.byType(ShaderMask),
    );

/// Left/right alpha of the mask's gradient (1 = opaque text, 0 = faded out).
({double left, double right}) _maskEdges(WidgetTester tester) {
  expect(_marqueeMask, findsOneWidget);
  // The mask's gradient cannot be read back from the shader; re-derive the
  // edge alphas from the live offset through the shared helper.
  final t = tester.widget<Transform>(_marqueeTransform);
  final offset = -t.transform.getTranslation().x;
  final state = tester.state(find.byType(MarqueeText)) as dynamic;
  final dist = state.debugCycleDistance as double;
  final f = marqueeEdgeFades(offset: offset, distance: dist, fadeWidth: 16);
  return (left: 1 - f.left, right: 1 - f.right);
}

double _offsetOf(WidgetTester tester) {
  final t = tester.widget<Transform>(_marqueeTransform);
  return -t.transform.getTranslation().x;
}

void main() {
  testWidgets('text that fits renders once, never translates, never fades',
      (tester) async {
    await tester.pumpWidget(_host(_short, width: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_short), findsOneWidget);
    expect(_marqueeTransform, findsNothing);
    expect(_marqueeMask, findsNothing);
  });

  testWidgets(
      'overflowing text is stationary before the cycle: right fade only',
      (tester) async {
    await tester.pumpWidget(_host(_long, width: 120));
    await tester.pump(); // post-frame: content measured, loop scheduled
    expect(find.text(_long), findsNWidgets(2)); // two copies for the loop
    expect(_offsetOf(tester), 0);
    expect(_marqueeMask, findsOneWidget); // permanent right-edge fade
    final edges = _maskEdges(tester);
    expect(edges.left, 1.0); // left edge sharp at rest
    expect(edges.right, 0.0); // right edge faded out
  });

  testWidgets(
      'left fade appears only while scrolling; right fade persists; cycle ends at 0',
      (tester) async {
    await tester.pumpWidget(_host(_long, width: 120));
    await tester.pump();
    // Past the pause, mid-way through the travel.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 300));
    final mid = _offsetOf(tester);
    expect(mid, greaterThan(16));
    expect(_marqueeMask, findsOneWidget);
    final moving = _maskEdges(tester);
    expect(moving.left, 0.0); // left fade fully in while moving
    expect(moving.right, 0.0);

    // Let the cycle complete (travel is well under 2s at 400 px/s).
    await tester.pump(const Duration(seconds: 3));
    expect(_offsetOf(tester), 0); // exact reset, no overshoot
    final rest = _maskEdges(tester);
    expect(rest.left, 1.0); // left fade gone again
    expect(rest.right, 0.0); // right fade stays
  });

  test('marqueeEdgeFades: right permanent, left follows the offset', () {
    const d = 300.0, w = 16.0;
    expect(marqueeEdgeFades(offset: 0, distance: d, fadeWidth: w),
        (left: 0.0, right: 1.0));
    expect(marqueeEdgeFades(offset: 8, distance: d, fadeWidth: w).left,
        closeTo(0.5, 1e-9));
    expect(marqueeEdgeFades(offset: 150, distance: d, fadeWidth: w),
        (left: 1.0, right: 1.0));
    expect(marqueeEdgeFades(offset: d - 4, distance: d, fadeWidth: w).left,
        closeTo(0.25, 1e-9));
    expect(marqueeEdgeFades(offset: d, distance: d, fadeWidth: w),
        (left: 0.0, right: 1.0));
    // Fade disabled → no mask on either edge; distance 0 → right only.
    expect(marqueeEdgeFades(offset: 10, distance: d, fadeWidth: 0),
        (left: 0.0, right: 0.0));
    expect(marqueeEdgeFades(offset: 0, distance: 0, fadeWidth: w),
        (left: 0.0, right: 1.0));
  });

  testWidgets('offset never exceeds the measured cycle distance',
      (tester) async {
    await tester.pumpWidget(_host(_long, width: 120));
    await tester.pump();
    final tp = TextPainter(
      text: const TextSpan(text: _long, style: _style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final maxTravel = tp.width + 48; // text + default gap
    tp.dispose();

    double peak = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (_marqueeTransform.evaluate().isNotEmpty) {
        peak = peak > _offsetOf(tester) ? peak : _offsetOf(tester);
      }
    }
    expect(peak, greaterThan(0));
    expect(peak, lessThanOrEqualTo(maxTravel + 0.01));
  });

  testWidgets('widening until the text fits stops the marquee at offset 0',
      (tester) async {
    await tester.pumpWidget(_host(_long, width: 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_offsetOf(tester), greaterThan(0));

    // Lyrics expanded: the action buttons disappear and width grows.
    await tester.pumpWidget(_host(_long, width: 600));
    await tester.pump();
    expect(_marqueeTransform, findsNothing);
    expect(_marqueeMask, findsNothing);
    expect(find.text(_long), findsOneWidget); // no duplicate on the far edge
    await tester.pump(const Duration(seconds: 2));
    expect(_marqueeTransform, findsNothing); // stays stopped
  });

  testWidgets('narrowing again restarts the marquee from a clean state',
      (tester) async {
    await tester.pumpWidget(_host(_long, width: 600));
    await tester.pump();
    expect(_marqueeTransform, findsNothing);

    // Lyrics collapsed: buttons back, width shrinks.
    await tester.pumpWidget(_host(_long, width: 120));
    await tester.pump();
    expect(find.text(_long), findsNWidgets(2));
    expect(_offsetOf(tester), 0);
    expect(_maskEdges(tester).left, 1.0);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_offsetOf(tester), greaterThan(0));
    await tester.pumpWidget(const SizedBox()); // dispose mid-cycle: no leak
  });

  testWidgets('a width change while overflowing restarts from 0',
      (tester) async {
    await tester.pumpWidget(_host(_long, width: 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_offsetOf(tester), greaterThan(0));

    await tester.pumpWidget(_host(_long, width: 160));
    await tester.pump();
    expect(_offsetOf(tester), 0);
    expect(_maskEdges(tester).left, 1.0); // sharp left again
  });

  testWidgets('a track change resets the marquee', (tester) async {
    await tester.pumpWidget(_host(_long, width: 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_offsetOf(tester), greaterThan(0));

    await tester.pumpWidget(_host(_short, width: 120));
    await tester.pump();
    expect(_marqueeTransform, findsNothing);
    expect(find.text(_short), findsOneWidget);

    await tester.pumpWidget(_host('$_long again', width: 120));
    await tester.pump();
    expect(_offsetOf(tester), 0);
  });

  testWidgets('prefix width counts toward the overflow decision',
      (tester) async {
    // 'Hi' alone fits in 60px; with a 50px prefix it does not.
    await tester.pumpWidget(_host(_short, width: 60));
    await tester.pump();
    expect(_marqueeTransform, findsNothing);

    await tester.pumpWidget(_host(
      _short,
      width: 60,
      prefix: const SizedBox(width: 50, height: 10),
    ));
    await tester.pump();
    await tester.pump();
    expect(_marqueeTransform, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('synced members: one that now fits never blocks the other',
      (tester) async {
    final sync = MarqueeController();
    Widget pair(double w1, double w2) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: w1,
                  child: MarqueeText(
                    text: _long,
                    style: _style,
                    controller: sync,
                    pauseDuration: const Duration(milliseconds: 100),
                    velocity: 800,
                  ),
                ),
                SizedBox(
                  width: w2,
                  child: MarqueeText(
                    text: '$_long B',
                    style: _style,
                    controller: sync,
                    pauseDuration: const Duration(milliseconds: 100),
                    velocity: 800,
                  ),
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(pair(120, 120));
    await tester.pump();
    // Both complete a cycle, then the second one gets room and stops.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(pair(120, 2000));
    await tester.pump();
    // The first must still be able to run new cycles on its own.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_marqueeTransform, findsOneWidget);
    expect(_offsetOf(tester), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });

  testWidgets('mini player layout: works in an unbounded-height column',
      (tester) async {
    // Mirrors MiniPlayer: 48dp art, Expanded → Column(center) with title and
    // artist marquees, then two icon buttons. The column gives its children
    // unbounded height, which the marquee must not try to fill.
    final sync = MarqueeController();
    Widget mini(double width) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 67,
                child: Row(
                  children: [
                    const SizedBox(width: 48, height: 48),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarqueeText(
                            text: _long,
                            style: _style,
                            controller: sync,
                            pauseDuration: const Duration(milliseconds: 100),
                            velocity: 800,
                          ),
                          MarqueeText(
                            text: _short,
                            style: _style,
                            controller: sync,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 36, height: 36),
                    const SizedBox(width: 42, height: 42),
                  ],
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(mini(300));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Title overflows (one Transform), artist fits (plain text).
    expect(_marqueeTransform, findsOneWidget);
    expect(find.text(_short), findsOneWidget);
    final box = tester.getSize(find.byType(MarqueeText).first);
    expect(box.height, lessThan(67)); // sized to the text, not the column
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_offsetOf(tester), greaterThan(0));
    expect(tester.takeException(), isNull);

    // Wide enough for everything: no marquee at all.
    await tester.pumpWidget(mini(800));
    await tester.pump();
    expect(_marqueeTransform, findsNothing);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });
}
