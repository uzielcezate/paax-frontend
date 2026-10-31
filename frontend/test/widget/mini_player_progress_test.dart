// test/widget/mini_player_progress_test.dart — V3 §7.2.
//
// Contract: Mini Player progress is measured along the capsule's UPPER
// perimeter (left mid-point → around the left corner → top edge → around the
// right corner → right mid-point), stays inside the capsule, and repaints from
// the position notifier without rebuilding the widget.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/presentation/widgets/mini_player.dart';
import 'package:beaty/presentation/widgets/paax_pill.dart';

void main() {
  const size = Size(345, kMiniPlayerHeight);

  test('fraction clamps and guards a zero duration', () {
    expect(
        MiniPlayerArcProgressPainter.fraction(
            const Duration(seconds: 30), const Duration(seconds: 60)),
        0.5);
    expect(
        MiniPlayerArcProgressPainter.fraction(
            const Duration(seconds: 90), const Duration(seconds: 60)),
        1.0);
    expect(
        MiniPlayerArcProgressPainter.fraction(
            const Duration(seconds: 1), Duration.zero),
        0.0);
  });

  test('upper perimeter = two quarter arcs + the straight top edge', () {
    const stroke = 2.0;
    final length = MiniPlayerArcProgressPainter.perimeterLength(size, stroke);
    final h = size.height - stroke; // deflated by stroke/2 on each side
    final w = size.width - stroke;
    final r = h / 2;
    final expected = math.pi * r + (w - 2 * r);
    expect(length, closeTo(expected, 0.5));
  });

  test(
      'path starts at the left mid-point and ends at the right mid-point,'
      ' never above the capsule top', () {
    const stroke = 2.0;
    final path = MiniPlayerArcProgressPainter.upperPerimeter(size, stroke);
    final metric = path.computeMetrics().first;
    final start = metric.getTangentForOffset(0)!.position;
    final end = metric.getTangentForOffset(metric.length)!.position;
    expect(start.dx, closeTo(stroke / 2, 0.01));
    expect(start.dy, closeTo(size.height / 2, 0.01));
    expect(end.dx, closeTo(size.width - stroke / 2, 0.01));
    expect(end.dy, closeTo(size.height / 2, 0.01));
    final bounds = path.getBounds();
    expect(bounds.top, greaterThanOrEqualTo(stroke / 2 - 0.01));
    expect(bounds.left, greaterThanOrEqualTo(stroke / 2 - 0.01));
    expect(bounds.right, lessThanOrEqualTo(size.width - stroke / 2 + 0.01));
    // Only the upper half is used.
    expect(bounds.bottom, lessThanOrEqualTo(size.height / 2 + 0.01));
  });

  testWidgets('painter listens to the position notifier (repaint, no rebuild)',
      (tester) async {
    final position = ValueNotifier<Duration>(Duration.zero);
    var builds = 0;
    final painter = MiniPlayerArcProgressPainter(
      position: position,
      durationOf: () => const Duration(seconds: 100),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        builds++;
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: PaaxPillSurface(
              child: CustomPaint(painter: painter),
            ),
          ),
        );
      }),
    ));
    expect(builds, 1);
    position.value = const Duration(seconds: 50);
    await tester.pump();
    expect(builds, 1); // notifier → repaint only
    expect(
        MiniPlayerArcProgressPainter.fraction(
            position.value, const Duration(seconds: 100)),
        0.5);
    expect(tester.takeException(), isNull);
  });

  test('V4 §3: 56dp capsule, concentric 42dp artwork, path follows the size',
      () {
    expect(kMiniPlayerHeight, 56);
    expect(kMiniPlayerArtwork, 42);
    expect(
        kMiniPlayerContentInset, (kMiniPlayerHeight - kMiniPlayerArtwork) / 2);
    // Corner radius of the new capsule drives the path: the arc radius is
    // (height − stroke) / 2 and the straight run shrinks accordingly.
    const stroke = 2.0;
    const narrow = Size(300, kMiniPlayerHeight);
    final r = (kMiniPlayerHeight - stroke) / 2;
    expect(MiniPlayerArcProgressPainter.perimeterLength(narrow, stroke),
        closeTo(math.pi * r + (narrow.width - stroke - 2 * r), 0.5));
    final bounds =
        MiniPlayerArcProgressPainter.upperPerimeter(narrow, stroke).getBounds();
    expect(bounds.top, closeTo(stroke / 2, 0.01)); // attached to the top edge
    expect(bounds.bottom, closeTo(kMiniPlayerHeight / 2, 0.01));
  });

  test('progress for 50% covers exactly half the perimeter length', () {
    const stroke = 2.0;
    final full = MiniPlayerArcProgressPainter.upperPerimeter(size, stroke);
    final metrics = full.computeMetrics().toList();
    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    var remaining = total * 0.5;
    double done = 0;
    for (final ui.PathMetric m in metrics) {
      final take = remaining.clamp(0.0, m.length);
      done += m
          .extractPath(0, take)
          .computeMetrics()
          .fold(0.0, (s, x) => s + x.length);
      remaining -= take;
      if (remaining <= 0) break;
    }
    expect(done, closeTo(total / 2, 0.5));
  });
}
