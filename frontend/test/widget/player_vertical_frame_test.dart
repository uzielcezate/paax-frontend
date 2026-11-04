// test/widget/player_vertical_frame_test.dart — Full Player refinement V3 §3.
//
// Invariant: Artwork mode (A) and Compact Lyrics mode (B) share one
// constrained slot, so every control below the slot has identical vertical
// coordinates in both. Expanded Lyrics (C) is a separate state that hides the
// controls and gives the slot the full height.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/presentation/widgets/player_layout_metrics.dart';
import 'package:beaty/presentation/widgets/player_vertical_frame.dart';

const _w = 393.0, _h = 779.0; // 851 − 24 top − 48 bottom

final _metrics = PlayerControlMetrics.forWidth(_w - 48);
final _layout = _metrics.verticalLayout(safeHeight: _h, contentWidth: _w - 48);

/// The frame fills a phone-sized test surface (the default 800×600 surface is
/// shorter than the player), so [_h] is the full safe-area height.
Future<void> _pump(WidgetTester tester,
    {required Widget slot, bool expanded = false}) async {
  tester.view.physicalSize = const Size(_w, _h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PlayerVerticalFrame(
        metrics: _metrics,
        layout: _layout,
        lyricsExpanded: expanded,
        header: const SizedBox(key: Key('header')),
        slot: slot,
        info: const SizedBox(key: Key('info'), height: 64),
        progress: const SizedBox(key: Key('progress'), height: 40),
        controls: SizedBox(key: const Key('controls'), height: _metrics.rowHeight),
        lower: const SizedBox(key: Key('lower'), height: 48),
      ),
    ),
  ));
}

/// State A: artwork pinned to the top of the slot.
Widget get _artwork => Column(children: [
      SizedBox(
          key: const Key('art'),
          width: _layout.artworkSize,
          height: _layout.artworkSize),
      const Spacer(),
    ]);

/// State B: a lyrics child whose intrinsic height is far taller than the slot
/// (hundreds of lines) — it must be clipped by the slot, never grow it.
Widget get _lyrics => Column(children: [
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxHeight: PlayerControlMetrics.compactLyricsHeight),
            child: ListView(
              key: const Key('lyrics'),
              children: List.generate(
                  300, (i) => SizedBox(height: 56, child: Text('line $i'))),
            ),
          ),
        ),
      ),
      const SizedBox(key: Key('handle'), height: 36),
    ]);

Map<String, double> _tops(WidgetTester tester) => {
      for (final k in ['info', 'progress', 'controls', 'lower'])
        k: tester.getTopLeft(find.byKey(Key(k))).dy,
    };

void main() {
  testWidgets('A → B → A: controls keep identical vertical coordinates',
      (tester) async {
    await _pump(tester, slot: _artwork);
    expect(tester.takeException(), isNull);
    final a = _tops(tester);

    await _pump(tester, slot: _lyrics);
    expect(tester.takeException(), isNull);
    final b = _tops(tester);
    expect(b, a);
    // The lyrics viewport is bounded and centred inside the slot.
    final lyricsBox = tester.getSize(find.byKey(const Key('lyrics')));
    expect(lyricsBox.height, PlayerControlMetrics.compactLyricsHeight);
    final slotTop = PlayerControlMetrics.headerHeight + PlayerControlMetrics.headerGap;
    expect(tester.getTopLeft(find.byKey(const Key('lyrics'))).dy, greaterThan(slotTop));

    await _pump(tester, slot: _artwork);
    expect(_tops(tester), a);
  });

  testWidgets('B → C → B: expanded lyrics hides controls, collapse restores',
      (tester) async {
    await _pump(tester, slot: _lyrics);
    final b = _tops(tester);

    await _pump(tester, slot: _lyrics, expanded: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('controls')), findsNothing);
    expect(find.byKey(const Key('lower')), findsNothing);
    // Full height for the lyrics: progress sits at the very bottom.
    final progressBottom = tester.getBottomLeft(find.byKey(const Key('progress'))).dy;
    expect(progressBottom, closeTo(_h - PlayerVerticalFrame.expandedBottomGap, 0.01));
    expect(tester.getTopLeft(find.byKey(const Key('info'))).dy, greaterThan(b['info']!));

    await _pump(tester, slot: _lyrics);
    expect(_tops(tester), b);
  });

  testWidgets('A → B → C → B → A round trip is stable', (tester) async {
    await _pump(tester, slot: _artwork);
    final a = _tops(tester);
    await _pump(tester, slot: _lyrics);
    expect(_tops(tester), a);
    await _pump(tester, slot: _lyrics, expanded: true);
    await _pump(tester, slot: _lyrics);
    expect(_tops(tester), a);
    await _pump(tester, slot: _artwork);
    expect(_tops(tester), a);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the slot height comes from the budget, not the child', (tester) async {
    await _pump(tester, slot: _artwork);
    final infoTop = _tops(tester)['info']!;
    final expectedSlot = PlayerControlMetrics.headerHeight +
        PlayerControlMetrics.headerGap +
        _layout.artworkSize +
        PlayerControlMetrics.artworkToInfoGap +
        _layout.artworkToInfoExtra;
    // Title sits exactly artworkToInfoGap (+ slack share) under the artwork.
    expect(infoTop, closeTo(expectedSlot, 0.01));
    // Cast/queue row sits above bottomGap + bottomExtra from the bottom edge.
    final lowerBottom = tester.getBottomLeft(find.byKey(const Key('lower'))).dy;
    expect(lowerBottom,
        closeTo(_h - PlayerControlMetrics.bottomGap - _layout.bottomExtra, 0.01));
  });
}
