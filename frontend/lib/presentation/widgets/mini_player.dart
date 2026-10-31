import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/track.dart';
import '../state/playback_controller.dart';
import '../state/library_controller.dart';
import '../screens/main_wrapper.dart';
import '../../core/image/lh3_url_builder.dart';
import 'app_image.dart';
import 'marquee_text.dart';
import 'explicit_badge.dart';
import 'paax_pill.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final MarqueeController _marqueeSync = MarqueeController();

  @override
  void dispose() {
    _marqueeSync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track =
        context.select<PlaybackController, Track?>((c) => c.currentTrack);
    if (track == null) return const SizedBox.shrink();
    final playback = context.read<PlaybackController>();

    return GestureDetector(
      onTap: () => MainWrapper.shellKey.currentState?.openPlayer(),
      child: Padding(
        // Same horizontal inset as the nav capsule and list artwork (V3 §2).
        padding:
            EdgeInsets.symmetric(horizontal: PaaxLayout.floatingInset(context)),
        // UI Visual System V2 §5: same sculpted capsule as the nav bar.
        child: SizedBox(
          height: kMiniPlayerHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: PaaxPillSurface(
                  height: kMiniPlayerHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: kMiniPlayerContentInset, right: 14),
                    child: Row(
                      children: [
                        // Cover art — circular in the Mini Player only (V3 §7.1).
                        AppImage(
                          url: track.artworkUrl,
                          sizePx: Lh3UrlBuilder.miniPlayerSize,
                          width: kMiniPlayerArtwork,
                          height: kMiniPlayerArtwork,
                          fit: BoxFit.cover,
                          isCircular: true,
                          forceLoad: true,
                        ),
                        const SizedBox(width: 10),

                        // Title & Artist
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MarqueeText(
                                text: track.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: Colors.white,
                                ),
                                controller: _marqueeSync,
                                prefix: track.isExplicit
                                    ? const ExplicitBadge(
                                        foregroundColor: Colors.white,
                                        scale: 0.85)
                                    : null,
                              ),
                              MarqueeText(
                                text: track.displayArtist,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                                controller: _marqueeSync,
                              ),
                            ],
                          ),
                        ),

                        // Like button
                        Consumer<LibraryController>(
                          builder: (context, lib, _) => IconButton(
                            icon: Icon(
                              lib.isLiked(track)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 23,
                            ),
                            color: lib.isLiked(track)
                                ? Colors.white
                                : Colors.white70,
                            onPressed: () => lib.toggleLike(track),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                          ),
                        ),

                        // Play/Pause button
                        Selector<PlaybackController, bool>(
                          selector: (_, c) => c.isPlaying,
                          builder: (context, isPlaying, _) => IconButton(
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 30,
                            ),
                            color: Colors.white,
                            onPressed: () => context
                                .read<PlaybackController>()
                                .togglePlayPause(),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 42, minHeight: 42),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Progress — drawn along the capsule's upper perimeter
              // (V3 §7.2). The painter listens to the position notifier
              // directly, so progress ticks repaint only this layer and never
              // rebuild the Mini Player.
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: MiniPlayerArcProgressPainter(
                        position: playback.positionNotifier,
                        durationOf: () => playback.duration,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini Player geometry. The dock in `main_wrapper.dart` reserves
/// [kMiniPlayerZone] (= height + gap) for it.
const double kMiniPlayerHeight = PaaxLayout.miniPlayerHeight;

/// Circular artwork diameter: concentric with the capsule's rounded end
/// (V4 §3: 56dp capsule → 42dp artwork, 7dp ring).
const double kMiniPlayerArtwork = 42;

/// Left inset of the circular artwork inside the capsule
/// (= (capsule height − artwork) / 2, so the circle is concentric).
const double kMiniPlayerContentInset =
    (kMiniPlayerHeight - kMiniPlayerArtwork) / 2;

/// Paints playback progress as a stroke along the upper half of the Mini
/// Player's stadium outline: from the left mid-point, up and around the left
/// corner, across the top edge, and down around the right corner to the right
/// mid-point. Progress is measured along that path (not as a horizontal
/// rectangle), so it follows the rounded corners and never leaves the capsule.
class MiniPlayerArcProgressPainter extends CustomPainter {
  MiniPlayerArcProgressPainter({
    required this.position,
    required this.durationOf,
    this.strokeWidth = 2.0,
    this.trackColor = const Color(0x1AFFFFFF),
    this.progressColor = const Color(0xE6FFFFFF),
  }) : super(repaint: position);

  final ValueListenable<Duration> position;
  final Duration Function() durationOf;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  /// Fraction of the upper perimeter that is complete (0–1).
  static double fraction(Duration position, Duration duration) {
    final d = duration.inMilliseconds;
    if (d <= 0) return 0.0;
    return (position.inMilliseconds / d).clamp(0.0, 1.0);
  }

  /// The full upper-perimeter path for a capsule of [size], inset so a stroke
  /// of [strokeWidth] stays entirely inside the capsule.
  static Path upperPerimeter(Size size, double strokeWidth) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final r = rect.height / 2;
    final path = Path()
      ..moveTo(rect.left, rect.center.dy)
      // Left corner: from 180° (left mid) sweeping to 270° (top).
      ..arcTo(
          Rect.fromCircle(
              center: Offset(rect.left + r, rect.center.dy), radius: r),
          math.pi,
          math.pi / 2,
          false)
      ..lineTo(rect.right - r, rect.top)
      // Right corner: from 270° (top) sweeping to 360° (right mid).
      ..arcTo(
          Rect.fromCircle(
              center: Offset(rect.right - r, rect.center.dy), radius: r),
          -math.pi / 2,
          math.pi / 2,
          false);
    return path;
  }

  /// Length of the upper perimeter for a capsule of [size] (for tests).
  static double perimeterLength(Size size, double strokeWidth) {
    double total = 0;
    for (final m in upperPerimeter(size, strokeWidth).computeMetrics()) {
      total += m.length;
    }
    return total;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final full = upperPerimeter(size, strokeWidth);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Subtle track along the whole upper perimeter.
    canvas.drawPath(full, paint..color = trackColor);

    final f = fraction(position.value, durationOf());
    if (f <= 0) return;
    final metrics = full.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var remaining = total * f;
    final done = Path();
    for (final ui.PathMetric m in metrics) {
      if (remaining <= 0) break;
      final take = remaining.clamp(0.0, m.length);
      done.addPath(m.extractPath(0, take), Offset.zero);
      remaining -= take;
    }
    canvas.drawPath(done, paint..color = progressColor);
  }

  @override
  bool shouldRepaint(MiniPlayerArcProgressPainter old) =>
      old.position != position ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}
