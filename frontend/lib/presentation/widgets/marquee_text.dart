import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

/// ─── MarqueeController ─────────────────────────────────────────────────────
/// Optional sync controller. When two MarqueeText widgets share the same
/// controller, they start scrolling together and wait for the slower one
/// before restarting — keeping title and artist visually synchronized.
class MarqueeController extends ChangeNotifier {
  final Set<_MarqueeTextState> _members = {};
  bool _syncing = false;

  void _register(_MarqueeTextState m) => _members.add(m);
  void _unregister(_MarqueeTextState m) {
    _members.remove(m);
    _reconcile();
  }

  /// Called by each member when its scroll cycle completes, and whenever a
  /// member stops or starts needing to scroll (so a member that now fits can
  /// never leave the others waiting for a cycle that will not come).
  void _reconcile() {
    if (_syncing) return;
    final scrolling = _members.where((m) => m._needsScroll).toList();
    if (scrolling.isEmpty) return;
    if (scrolling.every((m) => m._cycleComplete)) {
      _syncing = true;
      for (final m in scrolling) {
        m._cycleComplete = false;
      }
      _syncing = false;
      for (final m in scrolling) {
        m._restartCycle();
      }
    }
  }
}

/// ─── MarqueeText ───────────────────────────────────────────────────────────
/// Constraint-aware single-line marquee.
///
/// Behaviour contract (see docs/features/player.md):
/// - The text is measured against the *actual* layout constraints (via
///   [LayoutBuilder]) and the current [TextScaler]; whenever the available
///   width changes the overflow decision is re-evaluated. Text that fits is
///   rendered as a plain, sharply clipped [Text] — never animated, never faded.
/// - Scrolling translates by exactly the rendered width of one
///   `[prefix + text]` block plus [gap]; the second copy then sits at offset 0,
///   so snapping the controller back to 0 is pixel-identical (no overshoot,
///   no snapback). The distance used by the painter and the distance used by
///   the animation are the same field, read at paint time.
/// - Edge fades are driven by the live scroll offset, not by the overflow
///   flag: at rest (offset 0, i.e. before a cycle starts and after it ends)
///   there is no fade; the fade ramps in over the first [fadeMaskWidth] px of
///   travel and ramps out over the last [fadeMaskWidth] px.
/// - Text / style / scale / width changes invalidate the running cycle via a
///   generation token, reset the offset to 0 and re-measure.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double gap;
  final Duration pauseDuration;
  final double velocity;
  final double fadeMaskWidth;
  final MarqueeController? controller;

  /// Optional widget rendered before the text (e.g. ExplicitBadge).
  final Widget? prefix;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.gap = 48,
    this.pauseDuration = const Duration(seconds: 2),
    this.velocity = 35.0,
    this.fadeMaskWidth = 16.0,
    this.controller,
    this.prefix,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  // ── Measurements ──
  double _availableWidth = 0; // from LayoutBuilder constraints
  double _textWidth = 0; // intrinsic text width (TextPainter, scaled)
  double _prefixWidth = 0; // rendered prefix width (0 when no prefix)
  double _contentWidth = 0; // rendered [prefix + text] block width
  TextScaler _measuredScaler = TextScaler.noScaling;
  String? _measuredText;
  TextStyle? _measuredStyle;

  /// Pixel distance of the cycle currently running. Read by the painter on
  /// every tick so the painter and the animation can never disagree.
  double _cycleDistance = 0;

  bool _needsScroll = false;
  bool _cycleComplete = false;
  bool _running = false;

  /// Incremented whenever the running cycle must be abandoned (text change,
  /// width change, no longer overflowing). Async loops check it after every
  /// await and bail out if it moved.
  int _generation = 0;

  /// Pause between cycles. Held so it can be cancelled on dispose / reset
  /// (a bare Future.delayed would outlive the widget).
  Timer? _pauseTimer;

  final GlobalKey _contentKey = GlobalKey();
  final GlobalKey _prefixKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    widget.controller?._register(this);
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._unregister(this);
      widget.controller?._register(this);
    }
    final contentChanged = old.text != widget.text ||
        old.style != widget.style ||
        (old.prefix == null) != (widget.prefix == null);
    if (contentChanged) {
      // Stale measurements for a different track must never drive a cycle.
      _prefixWidth = 0;
      _contentWidth = 0;
      _stopScrolling(resetFlag: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _pauseTimer?.cancel();
    widget.controller?._unregister(this);
    _anim.dispose();
    super.dispose();
  }

  // ── Measuring ──────────────────────────────────────────────────────────

  void _measureText(TextScaler scaler) {
    if (_measuredText == widget.text &&
        _measuredStyle == widget.style &&
        _measuredScaler == scaler) {
      return;
    }
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    _textWidth = tp.width;
    tp.dispose();
    _measuredText = widget.text;
    _measuredStyle = widget.style;
    _measuredScaler = scaler;
  }

  /// Width of the rendered [prefix + text] block. Falls back to the painter
  /// measurement when the block has not been laid out yet.
  void _measureContent() {
    final ro = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (ro != null && ro.hasSize && ro.size.width > 0) {
      _contentWidth = ro.size.width;
    } else {
      _contentWidth = _textWidth + _prefixWidth;
    }
  }

  /// Measures the rendered prefix after a frame; if its width changed, the
  /// overflow decision may change too, so rebuild.
  void _schedulePrefixMeasure() {
    if (widget.prefix == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ro = _prefixKey.currentContext?.findRenderObject() as RenderBox?;
      if (ro == null || !ro.hasSize) return;
      if ((ro.size.width - _prefixWidth).abs() > 0.5) {
        setState(() => _prefixWidth = ro.size.width);
      }
    });
  }

  double get _blockWidth => _textWidth + _prefixWidth;

  /// Distance of one full cycle: one rendered block plus the gap.
  double get _scrollDistance => _contentWidth + widget.gap;

  // ── Cycle control ──────────────────────────────────────────────────────

  void _stopScrolling({required bool resetFlag}) {
    _generation++;
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _anim.stop();
    if (_anim.value != 0) _anim.value = 0;
    _running = false;
    _cycleComplete = false;
    if (resetFlag) _needsScroll = false;
    widget.controller?._reconcile();
  }

  void _startScrolling() {
    if (_running) return;
    final token = ++_generation;
    _running = true;
    _cycleComplete = false;
    // Let the scrolling subtree lay out once so the rendered block can be
    // measured before the first cycle.
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePause(token));
  }

  bool _alive(int token) => mounted && token == _generation && _needsScroll;

  void _schedulePause(int token) {
    if (!_alive(token)) return;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(widget.pauseDuration, () => _beginTravel(token));
  }

  void _beginTravel(int token) {
    if (!_alive(token)) return;
    _measureContent();
    _cycleDistance = _scrollDistance;
    _anim.duration = Duration(
      milliseconds: math.max(
        1,
        (_cycleDistance / widget.velocity * 1000).round(),
      ),
    );
    // `.then` fires only on natural completion; a stop() mid-flight (reset,
    // width change, dispose) never reaches the reset below.
    _anim.forward(from: 0).then((_) => _onTravelComplete(token));
  }

  void _onTravelComplete(int token) {
    if (!_alive(token)) return;
    // At value 1.0 the painter translated by exactly _cycleDistance: the
    // second copy sits precisely where the first copy started. Resetting
    // to 0 is therefore pixel-identical — no overshoot, no snapback, and
    // each cycle restarts from an exact 0 so nothing accumulates.
    _anim.value = 0;

    if (widget.controller != null) {
      _cycleComplete = true;
      _running = false;
      widget.controller!._reconcile(); // restarts us once all have completed
      return;
    }
    _schedulePause(token);
  }

  void _restartCycle() {
    if (!mounted || !_needsScroll) return;
    _running = false;
    _startScrolling();
  }

  /// Re-evaluates the overflow decision for [available] width. Called from
  /// build (synchronously, so a change in width never shows a stale frame).
  void _syncOverflow(double available) {
    final widthChanged = (available - _availableWidth).abs() > 0.5;
    _availableWidth = available;
    final needs = available.isFinite && _blockWidth > available + 1;

    if (needs && !_needsScroll) {
      _needsScroll = true;
      _startScrolling();
    } else if (!needs && _needsScroll) {
      // Text fits now (e.g. the lyrics panel freed up width): stop, zero the
      // offset and drop the second copy + fades.
      _stopScrolling(resetFlag: true);
    } else if (needs && widthChanged) {
      // Still overflowing but the layout changed: abandon the in-flight cycle
      // so no offset computed for the old constraints survives.
      _stopScrolling(resetFlag: false);
      _startScrolling();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    _measureText(scaler);
    _schedulePrefixMeasure();

    return LayoutBuilder(
      builder: (context, constraints) {
        _syncOverflow(constraints.maxWidth);
        return _needsScroll ? _buildScrolling() : _buildStatic();
      },
    );
  }

  Widget _buildStatic() {
    return Row(
      children: [
        if (widget.prefix != null) KeyedSubtree(key: _prefixKey, child: widget.prefix!),
        Expanded(
          child: Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
      ],
    );
  }

  Widget _buildScrolling() {
    final block = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.prefix != null) widget.prefix!,
        Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
      ],
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // First copy: measured for the exact cycle distance. The prefix key
        // lives here so the overflow decision can account for its width.
        Row(
          key: _contentKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.prefix != null)
              KeyedSubtree(key: _prefixKey, child: widget.prefix!),
            Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
          ],
        ),
        SizedBox(width: widget.gap),
        block, // second copy, identical, for seamless looping
      ],
    );

    return ClipRect(
      child: AnimatedBuilder(
        animation: _anim,
        child: content,
        builder: (context, child) {
          final dist = _cycleDistance;
          final offset = _anim.value * dist;
          // Fade strength follows the live offset: 0 at rest, ramps in over
          // the first fadeMaskWidth px and out over the last fadeMaskWidth px.
          final fadeW = widget.fadeMaskWidth;
          final fade = fadeW <= 0 || dist <= 0
              ? 0.0
              : (math.min(offset, dist - offset) / fadeW).clamp(0.0, 1.0);

          // deferToChild: width = incoming max (clipped), height = content
          // height — so this also works inside an unbounded-height Column
          // (Mini Player) without trying to fill infinite space.
          final translated = OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            fit: OverflowBoxFit.deferToChild,
            child: Transform.translate(
              offset: Offset(-offset, 0),
              child: child,
            ),
          );
          if (fade <= 0) return translated; // stationary: sharp clip, no mask

          return ShaderMask(
            shaderCallback: (Rect bounds) {
              final w = bounds.width <= 0 ? 1.0 : bounds.width;
              final leftEdge = (fadeW / w).clamp(0.0, 0.15);
              final rightEdge = ((fadeW + 2) / w).clamp(0.0, 0.15);
              final edge = Colors.white.withValues(alpha: 1.0 - fade);
              return LinearGradient(
                colors: [edge, Colors.white, Colors.white, edge],
                stops: [0.0, leftEdge, 1.0 - rightEdge, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: translated,
          );
        },
      ),
    );
  }
}
