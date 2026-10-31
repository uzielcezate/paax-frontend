import 'package:flutter/material.dart';

import 'player_layout_metrics.dart';

/// The Full Player's vertical skeleton.
///
/// One shared, constrained slot ([slot]) holds either the artwork or the
/// compact lyrics; everything below it (info, progress, controls, lower
/// actions) is laid out from [metrics] / [layout] only, so switching the slot
/// content can never move the controls. The slot's height is whatever the
/// column leaves after the fixed rows, independent of the child's intrinsic
/// height; a child that is taller must clip or fade inside it.
///
/// [lyricsExpanded] is the separate "expanded lyrics" state: controls and
/// lower actions are hidden and the distributed slack is dropped so the
/// lyrics get the full height (unchanged behaviour).
class PlayerVerticalFrame extends StatelessWidget {
  const PlayerVerticalFrame({
    super.key,
    required this.metrics,
    required this.layout,
    required this.lyricsExpanded,
    required this.header,
    required this.slot,
    required this.info,
    required this.progress,
    required this.controls,
    required this.lower,
  });

  final PlayerControlMetrics metrics;
  final PlayerVerticalLayout layout;
  final bool lyricsExpanded;
  final Widget header;
  final Widget slot;
  final Widget info;
  final Widget progress;
  final Widget controls;
  final Widget lower;

  /// Info → progress gap in the expanded-lyrics state (pre-existing value).
  static const double expandedInfoToProgressGap = 10;

  /// Trailing gap in the expanded-lyrics state (pre-existing value).
  static const double expandedBottomGap = 8;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: PlayerControlMetrics.headerHeight, child: header),
        const SizedBox(height: PlayerControlMetrics.headerGap),
        Expanded(child: slot),
        info,
        SizedBox(
            height: lyricsExpanded
                ? expandedInfoToProgressGap
                : PlayerControlMetrics.infoToProgressGap),
        progress,
        if (!lyricsExpanded) ...[
          const SizedBox(height: PlayerControlMetrics.progressToControlsGap),
          controls,
          SizedBox(
              height: PlayerControlMetrics.controlsToLowerGap +
                  layout.controlsToLowerExtra),
          lower,
          SizedBox(height: PlayerControlMetrics.bottomGap + layout.bottomExtra),
        ] else
          const SizedBox(height: expandedBottomGap),
      ],
    );
  }
}
