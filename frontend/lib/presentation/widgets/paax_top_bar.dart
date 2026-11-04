// lib/presentation/widgets/paax_top_bar.dart — UI Visual System V2 §3 / V3.
//
// Shared local top bar for detail screens (Artist / Album / Playlist / Genre):
// a back icon pill on the left, an optional trailing icon pill on the right,
// and a centred title capsule that fades in when the screen's immersive header
// has scrolled away ([showTitle]).
//
// Geometry (V3): the bar region is `topPadding` + [height] (58dp) tall; the
// back and trailing pills are [PaaxLayout.topBarPill] (44dp) discs whose outer
// edges sit exactly on [PaaxLayout.floatingInset] — the same inset as the Mini
// Player, the nav capsule and list artwork — each inside a 48dp tap target.
// The title capsule is the same 44dp tall. Behind the bar a long atmospheric
// `#080808` fade ([PaaxFade]) plateaus behind the controls and dissolves over
// [PaaxLayout.topFadeTail]; it animates with the title, so there is no jump.

import 'package:flutter/material.dart';

import 'paax_pill.dart';

class PaaxTopBar extends StatelessWidget {
  const PaaxTopBar({
    super.key,
    required this.title,
    required this.showTitle,
    required this.onBack,
    this.trailing,
    this.height = PaaxLayout.topBarHeight,
    this.foregroundColor = Colors.white,
    this.alwaysFade = false,
    this.backIcon = Icons.arrow_back_ios_new_rounded,
    this.backSemanticLabel = 'Back',
  });

  final String title;

  /// Whether the title capsule (and the fade behind the bar) is visible.
  final bool showTitle;
  final VoidCallback onBack;

  /// Right-hand control, already sized to its own tap target (e.g. an
  /// `OverflowMenu`). It is drawn inside a [pillSize] sculpted disc.
  final Widget? trailing;
  final double height;
  final Color foregroundColor;

  /// Keep the fade on even while the title is hidden (screens without an
  /// immersive header behind the bar).
  final bool alwaysFade;
  final IconData backIcon;
  final String backSemanticLabel;

  /// Extra fade below the bar so content dissolves instead of hitting an edge.
  static const double fadeTail = PaaxLayout.topFadeTail;
  static const double pillSize = PaaxLayout.topBarPill;
  static const double titleHeight = PaaxLayout.topBarPill;
  static const double tapTarget = PaaxLayout.tapTarget;
  static const double backIconSize = 20;
  static const Duration duration = Duration(milliseconds: 150);

  /// Horizontal gap between a side pill and the title capsule.
  static const double titleGap = 12;

  /// Offset of a side control's 48dp tap box so the 44dp disc sits on [inset].
  static double controlOffset(double inset) =>
      inset - (tapTarget - pillSize) / 2;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final inset = PaaxLayout.floatingInset(context);
    final fadeOn = alwaysFade || showTitle;
    final plateau = topPadding + height / 2;
    final total = topPadding + height + fadeTail;
    final sideOffset = controlOffset(inset);
    final titleInset = inset + pillSize + titleGap;

    return SizedBox(
      height: total,
      child: Stack(
        children: [
          // Atmospheric fade behind the whole top-bar region (never a blur).
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: fadeOn ? 1.0 : 0.0,
                duration: duration,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: PaaxFade.gradient(
                      total: total,
                      plateau: plateau,
                      fromTop: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            height: height,
            child: Stack(
              children: [
                // Left: back pill — outer edge on the shared inset.
                Positioned(
                  left: sideOffset,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: PaaxIconPill(
                      icon: backIcon,
                      iconSize: backIconSize,
                      size: pillSize,
                      minTapSize: tapTarget,
                      foregroundColor: foregroundColor,
                      onTap: onBack,
                      semanticLabel: backSemanticLabel,
                    ),
                  ),
                ),
                // Centre: title capsule — absolute centre, independent of
                // the side controls.
                Positioned.fill(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: showTitle ? 1.0 : 0.0,
                      duration: duration,
                      child: IgnorePointer(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: titleInset),
                          child: PaaxPillSurface(
                            height: titleHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            alignment: Alignment.center,
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: foregroundColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right: trailing pill — outer edge on the shared inset.
                if (trailing != null)
                  Positioned(
                    right: sideOffset,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SizedBox(
                        width: tapTarget,
                        height: tapTarget,
                        child: Center(
                          child: PaaxPillSurface(
                            width: pillSize,
                            height: pillSize,
                            child: Center(child: trailing),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
