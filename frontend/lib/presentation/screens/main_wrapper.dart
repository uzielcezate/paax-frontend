import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../state/playback_controller.dart';
import '../widgets/mini_player.dart';
import '../widgets/hidden_video_player.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'player_screen.dart';
import '../../core/utils/safe_insets.dart';
import '../widgets/offline_banner.dart';
import '../widgets/paax_pill.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  static final GlobalKey<MainWrapperState> shellKey =
      GlobalKey<MainWrapperState>();

  /// One RouteObserver per tab navigator. Each detail screen's
  /// DynamicBackground subscribes to the observer of its own tab
  /// so it receives didPopNext when a route pushed on top is popped.
  ///
  /// IMPORTANT: Each Navigator gets its OWN observer instance.
  /// Sharing one observer across multiple Navigators causes
  /// "observer.navigator == null" assertion in debug and silent
  /// breakage in release.
  static final List<RouteObserver<ModalRoute<dynamic>>> tabObservers = [
    RouteObserver<ModalRoute<dynamic>>(), // Home
    RouteObserver<ModalRoute<dynamic>>(), // Search
    RouteObserver<ModalRoute<dynamic>>(), // Library
    RouteObserver<ModalRoute<dynamic>>(), // Profile
  ];

  /// Returns the RouteObserver for the currently active tab.
  /// DynamicBackground calls this to subscribe to the correct observer.
  static RouteObserver<ModalRoute<dynamic>> get activeObserver =>
      tabObservers[shellKey.currentState?._currentIndex ?? 0];

  @override
  State<MainWrapper> createState() => MainWrapperState();
}

class MainWrapperState extends State<MainWrapper>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  final List<int> _history = [];
  PlaybackController? _playbackController;

  // ── Full Player Overlay State ──
  bool _isPlayerOpen = false;
  late final AnimationController _playerAnimation;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  final List<Widget> _rootPages = [
    const HomeScreen(),
    const SearchScreen(),
    const LibraryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _playerAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 120),
    );

    // Always set light status bar (white icons on dark bg)
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  /// Open the full player overlay (called from MiniPlayer)
  void openPlayer() {
    if (_isPlayerOpen) return;
    setState(() => _isPlayerOpen = true);
    _playerAnimation.forward();
  }

  /// Close the full player overlay
  void closePlayer() {
    if (!_isPlayerOpen) return;
    _playerAnimation.reverse().then((_) {
      if (mounted) {
        setState(() => _isPlayerOpen = false);
      }
    });
  }

  /// Returns true if the back action was handled internally (pop or tab switch).
  /// Returns false if the app should probably exit or do default behavior.
  ///
  /// Priority order (same in debug AND release):
  ///   0. Close full player
  ///   1. Pop internal route in current tab (e.g. artist detail → search)
  ///   2. Go back to previous tab (history)
  ///   3. Go to Home if not already there
  ///   4. Exit app
  bool onBackPressed() {
    // 0. Close full player first if it's open
    if (_isPlayerOpen) {
      closePlayer();
      return true;
    }

    final NavigatorState? currentNavigator =
        _navigatorKeys[_currentIndex].currentState;

    // 1. Try to pop internal route in current tab
    if (currentNavigator != null && currentNavigator.canPop()) {
      currentNavigator.pop();
      return true;
    }

    // 2. Try to go back to previous tab
    if (_history.isNotEmpty) {
      final prevIndex = _history.removeLast();
      setState(() => _currentIndex = prevIndex);
      return true;
    }

    // 3. If no history, but not on Home, go to Home
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return true;
    }

    // 4. Not handled (at Home root, no history)
    return false;
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) {
      // Pop to root if tapping same tab
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() {
        _history.add(_currentIndex);
        _currentIndex = index;
      });
    }
  }

  void navigateTo(Route route) {
    if (_navigatorKeys[_currentIndex].currentState != null) {
      _navigatorKeys[_currentIndex].currentState!.push(route);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<PlaybackController>();
    if (_playbackController != controller) {
      _playbackController?.removeListener(_onPlaybackError);
      _playbackController = controller;
      _playbackController!.addListener(_onPlaybackError);
    }
  }

  void _onPlaybackError() {
    final msg = _playbackController?.errorMessage;
    if (msg != null && mounted) {
      _playbackController!.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _playbackController?.removeListener(_onPlaybackError);
    _playerAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasTrack = context.watch<PlaybackController>().currentTrack != null;
    final bottomPadding = SafeInsets.bottomInset(context);

    return PopScope(
      canPop: false, // We handle all back navigation ourselves
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final handled = onBackPressed();
        if (!handled) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const HiddenVideoPlayer(),
            IndexedStack(
              index: _currentIndex,
              children: _rootPages.asMap().entries.map((entry) {
                final int idx = entry.key;
                final Widget rootPage = entry.value;

                return Navigator(
                  key: _navigatorKeys[idx],
                  observers: [
                    // Each tab gets its OWN _NavRouteObserver (fresh instance)
                    _NavRouteObserver(onChanged: () {}),
                    // Each tab gets its OWN RouteObserver (from the per-tab list)
                    MainWrapper.tabObservers[idx],
                  ],
                  onGenerateRoute: (settings) {
                    WidgetBuilder builder;
                    if (settings.name == '/') {
                      builder = (context) => rootPage;
                    } else {
                      builder = (context) => rootPage; // Fallback
                    }

                    return MaterialPageRoute(
                        builder: (context) => AnimatedPadding(
                              duration: const Duration(milliseconds: 50),
                              curve: Curves.easeOut,
                              padding: EdgeInsets.zero,
                              child: builder(context),
                            ),
                        settings: settings);
                  },
                );
              }).toList(),
            ),

            // ── Offline indicator (Phase 3.4.2) ──
            // Overlaid rather than inserted into the layout, so it cannot shift
            // any existing spacing, header measurement, or collage geometry.
            // Renders nothing when online.
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).padding.top,
              child: const IgnorePointer(child: OfflineBanner()),
            ),

            // ── Bottom Chrome: fade + mini player + nav icons ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RepaintBoundary(
                child: _buildBottomDock(hasTrack, bottomPadding),
              ),
            ),

            // ── Full Player Overlay ──
            if (_isPlayerOpen)
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 1.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _playerAnimation,
                  curve: Curves.ease,
                )),
                child: const PlayerScreen(),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom dock: atmospheric fade → mini player → nav capsule.
  /// The fade makes scrolling content dissolve under the controls.
  Widget _buildBottomDock(bool hasTrack, double bottomSafePadding) {
    const double navHeight = PaaxLayout.navHeight;
    const double miniPlayerZone = kMiniPlayerZone;
    // Extra fade above everything so content starts dissolving early (V3 §4).
    const double fadeExtra = PaaxLayout.bottomFadeExtra;

    // Shared bottom offset of the floating stack: system safe inset + one
    // clearance token (V4 §2). Applied once, here, for both components.
    final double dockBottom =
        bottomSafePadding + PaaxLayout.dockBottomClearance;
    final double contentHeight =
        (hasTrack ? miniPlayerZone : 0) + navHeight + dockBottom;
    final double totalHeight = contentHeight + fadeExtra;
    final double inset = PaaxLayout.floatingInset(context);

    return SizedBox(
      height: totalHeight,
      child: Stack(
        children: [
          // ── Fade: transparent → #080808, long ramp, plateau behind the
          // controls. Never a blur; never intercepts touches. This is the
          // ONLY bottom fade in the app (V4 §1): the per-screen bottom
          // gradients were removed so nothing stacks into a solid panel.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: PaaxFade.gradient(
                    total: totalHeight,
                    // Mirror of the top fade: the plateau ends at the nav
                    // capsule's vertical centre, then the same 72→0 % ramp
                    // runs up behind the Mini Player and [fadeExtra] beyond,
                    // so content stays faintly visible under the whole dock.
                    plateau: dockBottom + navHeight / 2,
                    fromTop: false,
                  ),
                ),
              ),
            ),
          ),

          // ── Mini player + Nav capsule (positioned at bottom) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mini player
                AnimatedSize(
                  duration: const Duration(milliseconds: 70),
                  curve: Curves.easeOut,
                  child:
                      hasTrack ? const MiniPlayer() : const SizedBox.shrink(),
                ),

                if (hasTrack) const SizedBox(height: PaaxLayout.dockGap),

                // Nav capsule (UI Visual System V2 §4 / V3 §6): one floating
                // sculpted pill, white capsule under the active destination,
                // aligned to the shared content inset.
                Padding(
                  padding: EdgeInsets.only(
                    left: inset,
                    right: inset,
                    bottom: dockBottom,
                  ),
                  child: PaaxBottomNavigation(
                    height: navHeight,
                    currentIndex: _currentIndex,
                    onTap: _onTabTapped,
                    items: const [
                      PaaxNavItem.svg(
                          outlined: 'assets/icons/home.svg',
                          filled: 'assets/icons/home-filled.svg',
                          label: 'Home'),
                      PaaxNavItem.svg(
                          outlined: 'assets/icons/magnifying-glass.svg',
                          filled: 'assets/icons/magnifying-glass-filled.svg',
                          label: 'Search'),
                      PaaxNavItem.icon(
                          outlined: Icons.library_music_outlined,
                          filled: Icons.library_music,
                          label: 'Library'),
                      PaaxNavItem.icon(
                          outlined: Icons.person_outline_rounded,
                          filled: Icons.person_rounded,
                          label: 'Profile'),
                    ],
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

/// Vertical space the Mini Player occupies in the dock (capsule + gap above
/// the nav capsule). Other screens (e.g. the Library FAB) offset by this.
const double kMiniPlayerZone = PaaxLayout.miniPlayerHeight + PaaxLayout.dockGap;

/// One destination of [PaaxBottomNavigation]: either a Material icon pair or
/// an SVG asset pair (outlined / filled).
class PaaxNavItem {
  const PaaxNavItem.icon({
    required IconData outlined,
    required IconData filled,
    required this.label,
  })  : outlinedIcon = outlined,
        filledIcon = filled,
        outlinedAsset = null,
        filledAsset = null;

  const PaaxNavItem.svg({
    required String outlined,
    required String filled,
    required this.label,
  })  : outlinedAsset = outlined,
        filledAsset = filled,
        outlinedIcon = null,
        filledIcon = null;

  final IconData? outlinedIcon;
  final IconData? filledIcon;
  final String? outlinedAsset;
  final String? filledAsset;
  final String label;
}

/// Floating sculpted navigation capsule (UI Visual System V2 §4 / V3 §6).
///
/// Same destinations, icon identities and tap behaviour as the previous flat
/// row; the selected state is a white elongated capsule — almost as tall as
/// the bar, inset [PaaxLayout.navIndicatorInset] — that slides between
/// equal-width slots, so the outer capsule never resizes.
class PaaxBottomNavigation extends StatelessWidget {
  const PaaxBottomNavigation({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height = PaaxLayout.navHeight,
  });

  final List<PaaxNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;

  /// Glyph size inside the capsule.
  static const double iconSize = 28;

  /// Active indicator width for a slot of [slotWidth]: the token width, but
  /// never wider than the slot minus the same inset the indicator keeps from
  /// the capsule's top and bottom edges.
  static double indicatorWidth(double slotWidth) {
    final max = slotWidth - 2 * PaaxLayout.navIndicatorInset;
    return PaaxLayout.navIndicatorWidth.clamp(0.0, max < 0 ? 0.0 : max);
  }

  @override
  Widget build(BuildContext context) {
    final count = items.length;
    final alignX = count <= 1 ? 0.0 : -1.0 + 2.0 * currentIndex / (count - 1);
    final indicatorHeight = height - 2 * PaaxLayout.navIndicatorInset;

    return PaaxPillSurface(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / count;
          return Stack(
            children: [
              // Sliding white selection capsule — one slot wide, centred.
              AnimatedAlign(
                alignment: Alignment(alignX, 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  width: slotWidth,
                  height: height,
                  child: Center(
                    child: PaaxPillSurface(
                      width: indicatorWidth(slotWidth),
                      height: indicatorHeight,
                      active: true,
                      showShadow: false,
                      child: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++) _slot(i, items[i]),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _slot(int index, PaaxNavItem item) {
    final selected = index == currentIndex;
    final color = selected
        ? PaaxPillTheme.activeForeground
        : PaaxPillTheme.inactiveForeground;
    final Widget glyph;
    if (item.outlinedAsset != null) {
      glyph = SizedBox(
        width: iconSize,
        height: iconSize,
        child: SvgPicture.asset(
          selected ? item.filledAsset! : item.outlinedAsset!,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          fit: BoxFit.contain,
        ),
      );
    } else {
      glyph = Icon(
        selected ? item.filledIcon : item.outlinedIcon,
        color: color,
        size: iconSize,
      );
    }
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: GestureDetector(
          onTap: () => onTap(index),
          behavior: HitTestBehavior.translucent,
          child: SizedBox.expand(child: Center(child: glyph)),
        ),
      ),
    );
  }
}

/// Lightweight route observer that calls [onChanged] whenever a route is
/// pushed or popped inside a tab Navigator.
class _NavRouteObserver extends NavigatorObserver {
  final VoidCallback onChanged;
  _NavRouteObserver({required this.onChanged});

  @override
  void didPush(Route route, Route? previousRoute) => onChanged();
  @override
  void didPop(Route route, Route? previousRoute) => onChanged();
  @override
  void didRemove(Route route, Route? previousRoute) => onChanged();
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => onChanged();
}
