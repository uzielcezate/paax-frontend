// lib/presentation/widgets/paax_pill.dart — UI Visual System V2/V3.
//
// "Monochrome sculpted pills": one centralized surface recipe shared by the
// bottom navigation, the Mini Player, top-bar icon pills, segmented filter
// pills, search fields and the circular secondary action buttons.
//
// The look is a slightly elevated, machined capsule:
//   • fill       — uniform, opaque #111111 (V3: no gradient inside the pill)
//   • bevel      — 1 logical px; #666666 highlight along the upper edge, fading
//                  down the sides, none at the bottom
//   • shadow     — soft black drop shadow underneath
//   • active     — solid #FFFFFF with #080808 glyph / text
//
// Implementation notes (perf contract, see spec §11):
//   • Plain ShapeDecoration + BoxShadow + a *gradient* border painted by a tiny
//     CustomPainter. No BackdropFilter, no ImageFilter, no Opacity layers.
//     Every decoration is a const or a cached static.
//   • The Full Player does NOT import this file (spec §9). Changing anything
//     here cannot move or restyle the player.

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';

/// Design tokens for the sculpted-pill system. Values are the spec contract.
class PaaxPillTheme {
  PaaxPillTheme._();

  // ── Surface ──
  /// Uniform pill fill (V3 §1). Opaque, no gradient.
  static const Color fill = Color(0xFF111111);
  static const Color bevel = Color(0xFF666666);
  static const double bevelWidth = 1.0;

  /// Bevel opacity along the top edge, the sides and the bottom edge.
  static const double bevelTopOpacity = 0.50;
  static const double bevelSideOpacity = 0.16;
  static const double bevelBottomOpacity = 0.0;

  // ── Active / inactive ──
  static const Color activeFill = Color(0xFFFFFFFF);
  static const Color activeForeground = Color(0xFF080808);
  static const Color inactiveForeground = Color(0xFFA0A0A0);
  static const Color placeholder = Color(0xFF8A8A8A);

  /// Search fields use a quieter bevel (spec §7: border `#191919`).
  static const Color searchBorder = Color(0xFF191919);

  // ── Fades (spec §1: #080808 → transparent, never a blur) ──
  static const Color fadeColor = AppColors.background;

  /// Subtle elevation shadow under every pill.
  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Vertical bevel gradient: bright top edge → dim sides → nothing at the
  /// bottom. Painted as a 1px stroke along the pill outline.
  static final LinearGradient bevelGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      bevel.withValues(alpha: bevelTopOpacity),
      bevel.withValues(alpha: bevelSideOpacity),
      bevel.withValues(alpha: bevelBottomOpacity),
    ],
    stops: const [0.0, 0.45, 1.0],
  );

  /// Quieter bevel for search fields.
  static final LinearGradient searchBevelGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      bevel.withValues(alpha: 0.28),
      searchBorder,
      searchBorder,
    ],
    stops: const [0.0, 0.5, 1.0],
  );
}

/// Centralized geometry for the floating chrome (V3 §2–§3). Every floating
/// surface (top bar pills, Mini Player, bottom navigation) reads its size and
/// its horizontal inset from here — never a per-screen number.
class PaaxLayout {
  PaaxLayout._();

  /// The one horizontal content inset of the app (V4 §4): shared by the Top
  /// Bar controls, the Mini Player, the Bottom Navigation capsule, section
  /// headings, the first item of horizontal carousels, full-width action
  /// buttons and main content lists. It is the existing content inset
  /// ([Responsive.horizontalPadding], 6 % of width clamped 16–24dp), i.e. the
  /// left edge of list artwork such as the Popular tracks on an artist page.
  static double contentHorizontalInset(BuildContext context) =>
      Responsive.horizontalPadding(context);

  /// Alias kept for the floating chrome call sites; same value as
  /// [contentHorizontalInset] — there is a single alignment system.
  static double floatingInset(BuildContext context) =>
      contentHorizontalInset(context);

  /// Same value from a raw width (for tests and painters without a context).
  static double floatingInsetForWidth(double width) =>
      (width * 0.06).clamp(16.0, 24.0);

  /// Height of a detail-screen top bar region below the status inset.
  static const double topBarHeight = 58;

  /// Diameter of the Back / More circular pills and height of the title
  /// capsule and of the search field that sits beside a back pill.
  static const double topBarPill = 44;

  /// Minimum tap target wrapped around a pill.
  static const double tapTarget = 48;

  /// Outer bottom-navigation capsule height (V4 §3: 85 % of the V3 64dp).
  static const double navHeight = 54;

  /// Inset between the capsule edge and the white active indicator.
  static const double navIndicatorInset = 4;

  /// Active indicator: an elongated capsule, almost as tall as the bar
  /// (scaled with the capsule: 46 × 62dp).
  static const double navIndicatorHeight = navHeight - 2 * navIndicatorInset;
  static const double navIndicatorWidth = 62;

  /// Mini Player capsule height (V4 §3: 85 % of the V3 66dp) and the gap
  /// between it and the nav capsule.
  static const double miniPlayerHeight = 56;
  static const double dockGap = 6;

  /// Extra clearance between the nav capsule and the system gesture
  /// indicator, added on top of the bottom safe inset (V4 §2). One token so
  /// the Mini Player and the nav capsule move together.
  static const double dockBottomClearance = 14;

  /// Atmospheric fade tails (how far a fade extends past its controls).
  static const double topFadeTail = 80;

  /// How far above the Mini Player / nav capsule the dock fade keeps
  /// dissolving content (V4 §1: long, like the top fade's tail).
  static const double bottomFadeExtra = 96;
}

/// The sculpted surface itself: uniform fill, gradient bevel, soft shadow,
/// fully rounded (stadium) unless [radius] is given. Sizes itself to [child]
/// (or [width]/[height]). [active] swaps to the flat white selection surface.
class PaaxPillSurface extends StatelessWidget {
  const PaaxPillSurface({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.radius,
    this.active = false,
    this.showShadow = true,
    this.quietBevel = false,
    this.padding,
    this.alignment,
  });

  final Widget child;
  final double? width;
  final double? height;

  /// Corner radius. `null` → stadium (fully rounded for any height).
  final double? radius;
  final bool active;
  final bool showShadow;

  /// Use the quieter search-field bevel (`#191919`).
  final bool quietBevel;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final shape = radius == null
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius!))
            as OutlinedBorder;

    Widget surface = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: active ? PaaxPillTheme.activeFill : PaaxPillTheme.fill,
        shadows: showShadow ? PaaxPillTheme.shadow : null,
      ),
      child: CustomPaint(
        foregroundPainter: active
            ? null
            : _BevelPainter(
                shape: shape,
                gradient: quietBevel
                    ? PaaxPillTheme.searchBevelGradient
                    : PaaxPillTheme.bevelGradient,
              ),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: alignment == null
              ? child
              : Align(alignment: alignment!, child: child),
        ),
      ),
    );

    if (width != null || height != null) {
      surface = SizedBox(width: width, height: height, child: surface);
    }
    return surface;
  }
}

/// Paints a 1px bevel stroke along the inside of [shape] with [gradient].
class _BevelPainter extends CustomPainter {
  const _BevelPainter({required this.shape, required this.gradient});

  final OutlinedBorder shape;
  final LinearGradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Inset by half the stroke so the whole 1px line stays inside the fill.
    final path = shape.getOuterPath(rect.deflate(PaaxPillTheme.bevelWidth / 2));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = PaaxPillTheme.bevelWidth
      ..shader = gradient.createShader(rect);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BevelPainter old) =>
      old.shape != shape || old.gradient != gradient;
}

/// A circular icon pill (top-bar back / menu / action buttons).
///
/// The visual disc is [size] dp ([PaaxLayout.topBarPill] by default); the tap
/// target is at least [minTapSize] (48dp by default) so proportions can stay
/// compact without losing accessibility. [active] renders the white surface.
class PaaxIconPill extends StatelessWidget {
  const PaaxIconPill({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = PaaxLayout.topBarPill,
    this.iconSize = 20,
    this.active = false,
    this.foregroundColor,
    this.minTapSize = PaaxLayout.tapTarget,
    this.semanticLabel,
    this.showShadow = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool active;

  /// Overrides the inactive glyph colour (defaults to white).
  final Color? foregroundColor;
  final double minTapSize;
  final String? semanticLabel;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final fg = active
        ? PaaxPillTheme.activeForeground
        : (foregroundColor ?? Colors.white);
    return PaaxPillTap(
      onTap: onTap,
      minTapSize: minTapSize,
      semanticLabel: semanticLabel,
      child: PaaxPillSurface(
        width: size,
        height: size,
        active: active,
        showShadow: showShadow,
        child: Center(child: Icon(icon, size: iconSize, color: fg)),
      ),
    );
  }
}

/// Wraps a child in a tap target of at least [minTapSize] square, centred on
/// the child, without changing the child's painted size.
class PaaxPillTap extends StatelessWidget {
  const PaaxPillTap({
    super.key,
    required this.child,
    required this.onTap,
    this.minTapSize = PaaxLayout.tapTarget,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double minTapSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minWidth: minTapSize, minHeight: minTapSize),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// One segmented filter / tab pill: white when [selected], sculpted when not.
/// Content-sized (horizontal [padding]) and [height] tall; callers decide
/// equal-width vs content-width by how they lay these out.
class PaaxSegmentPill extends StatelessWidget {
  const PaaxSegmentPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 34,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.textStyle,
    this.inactiveForeground,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final EdgeInsetsGeometry padding;

  /// Base text style; colour is overridden per state.
  final TextStyle? textStyle;

  /// Inactive text colour (default [PaaxPillTheme.inactiveForeground]).
  final Color? inactiveForeground;

  @override
  Widget build(BuildContext context) {
    final base =
        textStyle ?? const TextStyle(fontWeight: FontWeight.bold, fontSize: 13);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: PaaxPillSurface(
          height: height,
          active: selected,
          padding: padding,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            style: base.copyWith(
              color: selected
                  ? PaaxPillTheme.activeForeground
                  : (inactiveForeground ?? PaaxPillTheme.inactiveForeground),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of [PaaxSegmentPill]s. Preserves the callers'
/// tab order, horizontal scrolling and content-based sizing.
class PaaxSegmentedPills extends StatelessWidget {
  const PaaxSegmentedPills({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 34,
    this.gap = 8,
    this.padding = const EdgeInsets.only(left: 16),
    this.pillPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.textStyle,
    this.inactiveForeground,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;
  final double gap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry pillPadding;
  final TextStyle? textStyle;
  final Color? inactiveForeground;

  /// Vertical room added around the pills so the drop shadow is not clipped.
  static const double shadowRoom = 8;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height + shadowRoom,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        primary: false,
        clipBehavior: Clip.none,
        padding:
            padding.add(const EdgeInsets.symmetric(vertical: shadowRoom / 2)),
        itemCount: labels.length,
        separatorBuilder: (_, __) => SizedBox(width: gap),
        itemBuilder: (context, i) => PaaxSegmentPill(
          label: labels[i],
          selected: i == selectedIndex,
          onTap: () => onSelected(i),
          height: height,
          padding: pillPadding,
          textStyle: textStyle,
          inactiveForeground: inactiveForeground,
        ),
      ),
    );
  }
}

/// Sculpted search-field shell. The caller supplies the [TextField] so
/// controllers, focus, debounce and clear actions stay exactly as they were.
class PaaxSearchPill extends StatelessWidget {
  const PaaxSearchPill({
    super.key,
    required this.child,
    this.height = PaaxLayout.topBarPill,
  });

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return PaaxPillSurface(
      height: height,
      quietBevel: true,
      child: Center(child: child),
    );
  }
}

/// Atmospheric fade curve (V3 §4): a long multi-stop ramp instead of a short
/// two-stop one. [PaaxFade.ramp] lists the opacity at six evenly spaced
/// positions from fully transparent to the darkest point behind the controls.
class PaaxFade {
  PaaxFade._();

  /// Opacity from the transparent end towards the controls.
  static const List<double> ramp = [0.0, 0.08, 0.22, 0.45, 0.72, 0.95];

  /// Darkest opacity, held flat behind the controls.
  static double get peak => ramp.last;

  /// Gradient for a region of [total] px whose first [plateau] px (from the
  /// controls' side) stay at [peak] and whose remaining px ramp down to zero.
  /// [fromTop] = controls at the top (fade downward); otherwise controls at the
  /// bottom (fade upward). [opacity] scales every stop (0 → invisible) so the
  /// fade can follow scroll without an `Opacity` layer.
  static LinearGradient gradient({
    required double total,
    required double plateau,
    bool fromTop = true,
    double opacity = 1.0,
  }) {
    final c = PaaxPillTheme.fadeColor;
    final p = total <= 0 ? 0.0 : (plateau / total).clamp(0.0, 1.0);
    final stops = <double>[0.0, p];
    final colors = <Color>[
      c.withValues(alpha: peak * opacity),
      c.withValues(alpha: peak * opacity),
    ];
    // Five ramp steps 0.72 → 0 spread evenly over the tail.
    final steps = ramp.length - 1; // 5
    for (var i = 1; i <= steps; i++) {
      stops.add(p + (1.0 - p) * i / steps);
      colors.add(c.withValues(alpha: ramp[steps - i] * opacity));
    }
    return LinearGradient(
      begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
      end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
      colors: colors,
      stops: stops,
    );
  }
}

/// Fade behind a pinned header region: [plateau] px of near-solid `#080808`
/// behind the controls, then a long [tail] that dissolves into the content.
/// Non-interactive; a plain gradient, never a blur. [opacity] lets callers tie
/// it to scroll offset without an `Opacity` layer.
class PaaxHeaderFade extends StatelessWidget {
  const PaaxHeaderFade({
    super.key,
    required this.plateau,
    this.tail = PaaxLayout.topFadeTail,
    this.opacity = 1.0,
  });

  final double plateau;
  final double tail;
  final double opacity;

  double get totalHeight => plateau + tail;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: totalHeight,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: PaaxFade.gradient(
              total: totalHeight,
              plateau: plateau,
              fromTop: true,
              opacity: opacity,
            ),
          ),
        ),
      ),
    );
  }
}

/// Edge fade behind a top bar or under the bottom dock: `#080808` →
/// transparent. A plain gradient, never a blur. Non-interactive.
class PaaxEdgeFade extends StatelessWidget {
  const PaaxEdgeFade.top({super.key, this.maxOpacity = 1.0}) : fromTop = true;
  const PaaxEdgeFade.bottom({super.key, this.maxOpacity = 1.0})
      : fromTop = false;

  final bool fromTop;
  final double maxOpacity;

  @override
  Widget build(BuildContext context) {
    final c = PaaxPillTheme.fadeColor;
    final colors = [
      for (var i = PaaxFade.ramp.length - 1; i >= 0; i--)
        c.withValues(alpha: PaaxFade.ramp[i] * maxOpacity),
    ];
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: colors,
            stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
