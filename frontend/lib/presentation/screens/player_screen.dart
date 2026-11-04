import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../state/playback_controller.dart';
import '../state/library_controller.dart';
import '../widgets/marquee_text.dart';
import '../widgets/player_layout_metrics.dart';
import '../widgets/player_vertical_frame.dart';

import '../widgets/overflow_menu.dart';
import '../widgets/app_image.dart';
import '../widgets/smooth_audio_progress_bar.dart';
import '../widgets/queue_bottom_sheet.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/explicit_badge.dart';
import '../widgets/synced_lyrics_view.dart';
import '../../domain/services/lyrics_service.dart';
import '../screens/album_detail_screen.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/main_wrapper.dart';
import '../../domain/entities/saved_album.dart';
import '../../domain/entities/track.dart';

import '../../core/utils/responsive.dart';
import '../../core/utils/string_utils.dart';
import '../../core/image/lh3_url_builder.dart';

const kPlayerHorizontalPadding = 24.0;

/// Full Player modes
enum PlayerMode { song, lyrics }

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double _dragOffset = 0;
  final MarqueeController _marqueeSync = MarqueeController();
  PlayerMode _mode = PlayerMode.song;
  bool _lyricsExpanded = false;

  // ── Lyrics state ──
  final LyricsService _lyricsService = LyricsService();
  List<LyricLine> _currentLyrics = [];
  bool _lyricsLoading = false;
  bool _lyricsAvailable = true;
  bool _lyricsAreSynced = false;
  String? _loadedLyricsForTrackId;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // Only allow dismiss drag in Song mode
    if (_mode != PlayerMode.song) return;
    if (details.delta.dy > 0 || _dragOffset > 0) {
      setState(() => _dragOffset = (_dragOffset + details.delta.dy).clamp(0, double.infinity));
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_mode != PlayerMode.song) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 100 || velocity > 700) {
      MainWrapper.shellKey.currentState?.closePlayer();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  /// Fetch lyrics for the given track if not already loaded.
  void _fetchLyricsIfNeeded(Track track) {
    if (_loadedLyricsForTrackId == track.id) return; // Already loaded/loading
    _loadedLyricsForTrackId = track.id;

    // Clear previous lyrics immediately
    setState(() {
      _currentLyrics = [];
      _lyricsLoading = true;
      _lyricsAvailable = true;
      _lyricsAreSynced = false;
    });

    _lyricsService.getLyrics(
      track.id,
      title: track.title,
      artist: track.artistName,
      album: track.albumTitle,
      trackDurationMs: track.duration * 1000,
    ).then((result) {
      if (!mounted) return;
      if (_loadedLyricsForTrackId != track.id) return; // Track changed during fetch
      setState(() {
        _currentLyrics = result.lines;
        _lyricsAvailable = result.isAvailable;
        _lyricsAreSynced = result.isSynced;
        _lyricsLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _marqueeSync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<PlaybackController, Track?>(
      selector: (_, c) => c.currentTrack,
      builder: (context, track, _) {
          if (track == null) return const Scaffold(body: Center(child: Text("No track playing")));

          final screenHeight = MediaQuery.of(context).size.height;
          final screenWidth = MediaQuery.of(context).size.width;
          // Use viewPadding — more reliable across OEM Android skins
          final viewPad = MediaQuery.of(context).viewPadding;
          final topInset = viewPad.top > 0 ? viewPad.top : MediaQuery.of(context).padding.top;
          final bottomInset = [viewPad.bottom, MediaQuery.of(context).padding.bottom, 8.0]
              .reduce((a, b) => a > b ? a : b);

          
          // ── Vertical budget ──
          // PlayerControlMetrics owns every fixed height below the header;
          // the artwork takes what is left and any remaining slack is split
          // between the artwork→title gap and the bottom edge, which lifts
          // the whole lower section instead of pinning it to the bottom.
          final contentWidth = screenWidth - 2 * kPlayerHorizontalPadding;
          final metrics = PlayerControlMetrics.forWidth(contentWidth);
          final layout = metrics.verticalLayout(
            safeHeight: screenHeight - topInset - bottomInset,
            contentWidth: contentWidth,
          );

          final playback = context.read<PlaybackController>();

          // Dismiss progress: 0.0 (idle) → 1.0 (fully dragged)
          final dismissProgress = (_dragOffset / (screenHeight * 0.35)).clamp(0.0, 1.0);

          return GestureDetector(
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: AnimatedContainer(
              duration: _dragOffset == 0
                  ? const Duration(milliseconds: 150)
                  : Duration.zero,
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, _dragOffset, 0),
              child: Opacity(
                opacity: (1.0 - dismissProgress * 0.3).clamp(0.6, 1.0),
                child: Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                // Background Image (Static & Blurred)
                RepaintBoundary(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AppImage(
                        url: track.artworkUrl,
                        sizePx: Lh3UrlBuilder.headerSize,
                        fit: BoxFit.cover,
                        forceLoad: true,
                      ),
                      BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                         child: Container(
                           color: Colors.black.withValues(alpha: 0.55),
                         ),
                       ),
                    ],
                  ),
                ),
                
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kPlayerHorizontalPadding),
                    // The frame owns the vertical rhythm: one shared slot for
                    // artwork / compact lyrics, so switching modes never moves
                    // the info, progress or controls (see PlayerVerticalFrame).
                    child: PlayerVerticalFrame(
                      metrics: metrics,
                      layout: layout,
                      lyricsExpanded: _lyricsExpanded,
                      // ── Header with mode switcher ──
                      header: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pill — perfectly centered via Stack
                          _buildModeSwitcher(),
                          // Left: close button
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                                onPressed: () => MainWrapper.shellKey.currentState?.closePlayer(),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: PlayerControlMetrics.minTouchTarget,
                                  minHeight: PlayerControlMetrics.minTouchTarget,
                                ),
                                icon: const Icon(Icons.keyboard_arrow_down,
                                    color: Colors.white,
                                    size: PlayerControlMetrics.headerChevronIcon)
                            ),
                          ),
                          // Right: overflow menu
                          Align(
                            alignment: Alignment.centerRight,
                            child: OverflowMenu(
                              type: MenuType.track,
                              track: track,
                              onNavigation: () => MainWrapper.shellKey.currentState?.closePlayer(),
                              isNowPlaying: true,
                              iconSize: PlayerControlMetrics.headerMenuIcon,
                            ),
                          ),
                        ],
                      ),
                      // ── Shared slot: artwork or compact lyrics ──
                      slot: _mode == PlayerMode.song
                          ? _buildSongContent(context, track, playback, layout)
                          : _buildLyricsContent(context, track, playback),
                      // ── Track Info ──
                      info: _buildTrackInfo(track),
                      // ── Progress Bar ──
                      progress: const SmoothAudioProgressBar(),
                      // ── Controls (may use part of the gutter) ──
                      controls: const OverflowBox(
                        alignment: Alignment.center,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        fit: OverflowBoxFit.deferToChild,
                        child: _PlayerControls(),
                      ),
                      lower: const _LowerActions(),
                    ),
                  ),
                ),
              ],
            ),
          ),
              ),
            ),
          );
      }
    );
  }

  // ── Mode Switcher Pill ──
  Widget _buildModeSwitcher() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModePill(
            icon: Icons.music_note_rounded,
            mode: PlayerMode.song,
          ),
          _buildModePill(
            label: 'Aa',
            mode: PlayerMode.lyrics,
          ),
        ],
      ),
    );
  }

  Widget _buildModePill({IconData? icon, String? label, required PlayerMode mode}) {
    final isActive = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _mode = mode;
        // Collapse expanded lyrics when switching to song mode
        if (mode == PlayerMode.song) _lyricsExpanded = false;
      }),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: icon != null
            ? Icon(icon, size: 18, color: isActive ? Colors.white : Colors.white54)
            : Text(
                label!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Colors.white : Colors.white54,
                ),
              ),
      ),
    );
  }

  
  // ── Song Mode Content (artwork near the header, slack below) ──
  Widget _buildSongContent(BuildContext context, Track track,
      PlaybackController playback, PlayerVerticalLayout layout) {
    return GestureDetector(

      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) {
          playback.playNext();
        } else if (velocity > 300) {
          playback.playPrevious();
        }
      },
      
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = PlayerControlMetrics.artworkToInfoGap +
              layout.artworkToInfoExtra;
          // The budget is an estimate (fonts scale); if the region is
          // smaller than expected the artwork shrinks instead of pushing the
          // title block out of the column.
          final artworkSize = constraints.maxHeight.isFinite
              ? math.min(layout.artworkSize,
                  math.max(0.0, constraints.maxHeight - gap))
              : layout.artworkSize;
          return Column(
        children: [
          SizedBox(
            width: artworkSize,
            height: artworkSize,
            child: Stack(

              alignment: Alignment.center,
              children: [
                Container(
                  width: artworkSize,
                  height: artworkSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: AppImage(
                    url: track.artworkUrl,
                    sizePx: Lh3UrlBuilder.fullPlayerSize,
                    width: artworkSize,
                    height: artworkSize,
                    fit: BoxFit.cover,
                    borderRadius: 20,
                    forceLoad: true,
                  ),
                ),
                // Loading overlay
                Selector<PlaybackController, bool>(
                  selector: (_, c) => c.isLoadingTrack,
                  builder: (_, isLoading, __) => isLoading
                      ? Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                        )
                      
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(height: gap),
        ],
          );
        },
      ),
    );
  }


  // ── Lyrics Mode Content ──
  Widget _buildLyricsContent(BuildContext context, Track track, PlaybackController playback) {
    // Trigger lyrics fetch for this track
    _fetchLyricsIfNeeded(track);

    final lyricsBody = GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) {
          playback.playNext();
        } else if (velocity > 300) {
          playback.playPrevious();
        }
      },
      child: _lyricsLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 2,
              ),
            )
          : !_lyricsAvailable
              ? const Center(
                  child: Text(
                    'Lyrics not available',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : SyncedLyricsView(
                  lyrics: _currentLyrics,
                  positionNotifier: playback.positionNotifier,
                  isSynced: _lyricsAreSynced,
                  onSeekToLine: _lyricsAreSynced
                      ? (time) { playback.seek(time); }
                      : null,
                ),
    );

    return Column(
      children: [
        Expanded(
          child: _lyricsExpanded
              ? lyricsBody
              // Compact mode: ≈3 synced entries centred in the artwork slot.
              // The viewport is bounded (never the lyrics' intrinsic height);
              // SyncedLyricsView fades its own top/bottom edges.
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxHeight: PlayerControlMetrics.compactLyricsHeight),
                    child: lyricsBody,
                  ),
                ),
        ),
        // ── Expand/collapse handle ──
        GestureDetector(
          onTap: () => setState(() => _lyricsExpanded = !_lyricsExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  _lyricsExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Track Info ──
  Widget _buildTrackInfo(Track track) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                   if (track.albumId.isNotEmpty) {
                      MainWrapper.shellKey.currentState?.closePlayer();
                      MainWrapper.shellKey.currentState?.navigateTo(
                         MaterialPageRoute(
                           builder: (_) => AlbumDetailScreen(
                              album: SavedAlbum(
                                 albumId: track.albumId,
                                 title: track.albumTitle.isNotEmpty
                                     ? track.albumTitle
                                     : '${track.title} Album',
                                 artworkUrl: track.artworkUrl,
                                 artistName: track.artistName,
                                 artistId: track.artistId ?? '',
                              ),
                           ),
                         ),
                      );
                   }
                },
                child: MarqueeText(
                  text: track.title, 
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 24, min: 20, max: 28), 
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  controller: _marqueeSync,
                  prefix: track.isExplicit
                      ? const ExplicitBadge(foregroundColor: Colors.white, scale: 1.1)
                      : null,
                ),
              ),
               const SizedBox(height: 4),
              GestureDetector(
                 behavior: HitTestBehavior.opaque,
                 onTap: () {
                    if (isPlaceholderArtist(track.artistName)) return;
                    final firstArtist = (track.artists != null && track.artists!.isNotEmpty)
                        ? track.artists!.first
                        : null;
                    final artistId = (firstArtist?['id'] ?? track.artistId ?? '').toString();
                    final artistName = firstArtist?['name'] ?? track.artistName;
                    if (artistId.isEmpty) return;
                    MainWrapper.shellKey.currentState?.closePlayer();
                    MainWrapper.shellKey.currentState?.navigateTo(
                      MaterialPageRoute(builder: (_) => ArtistDetailScreen(
                        artistId: artistId,
                        artistName: artistName,
                      )),
                    );
                 },
                 child: MarqueeText(
                   text: track.displayArtist,
                   style: TextStyle(
                     fontSize: Responsive.fontSize(context, 16, min: 14, max: 18),
                     color: AppColors.textSecondary,
                   ),
                   controller: _marqueeSync,
                 ),
              ),
            ],
          ),
        ),
        // Hide action buttons when lyrics are expanded
        if (!_lyricsExpanded) ...[
          // Add to Playlist Button
          IconButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => AddToPlaylistSheet(tracks: [track]),
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: PlayerControlMetrics.minTouchTarget,
              minHeight: PlayerControlMetrics.minTouchTarget,
            ),
            
            icon: Container(
              width: PlayerControlMetrics.addRing,
              height: PlayerControlMetrics.addRing,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white54,
                    width: PlayerControlMetrics.addRingBorder),
              ),

              child: const Icon(Icons.add,
                  color: Colors.white, size: PlayerControlMetrics.addIcon),
            ),
          ),
          const SizedBox(width: 4),
          // Like Button
          Consumer<LibraryController>(
            builder: (context, lib, _) {
                final isLiked = lib.isLiked(track);
                return IconButton(
                    onPressed: () => lib.toggleLike(track),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: PlayerControlMetrics.minTouchTarget,
                      minHeight: PlayerControlMetrics.minTouchTarget,
                    ),
                    icon: Icon(
                        isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isLiked ? Colors.white : Colors.white.withValues(alpha: 0.7),
                        size: PlayerControlMetrics.likeIcon,
                    )
                );
            }
          ),
        ],
      ],
    );
  }
}

// ── Player Controls ─────────────────────────────────────────────────────────

class _PlayerControls extends StatefulWidget {
  const _PlayerControls();

  @override
  State<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<_PlayerControls> {

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();

    
    // Parent is an OverflowBox with unbounded width: derive the width from the
    // screen instead (same input the artwork budget used).
    final contentWidth =
        MediaQuery.sizeOf(context).width - 2 * kPlayerHorizontalPadding;
    final m = PlayerControlMetrics.forWidth(contentWidth);
    BoxConstraints box(double side) =>
        BoxConstraints(minWidth: side, minHeight: side);

    return SizedBox(
          width: m.rowWidth,
          height: m.rowHeight,
          child: Row(

            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Shuffle
              Selector<PlaybackController, bool>(
                selector: (_, c) => c.isShuffle,
                builder: (_, isShuffle, __) => IconButton(
                  padding: EdgeInsets.zero,
                  constraints: box(m.shuffleBox),
                  icon: Icon(Icons.shuffle,
                      color: isShuffle ? AppColors.primaryEnd : Colors.white54,
                      size: m.shuffleIcon),
                  onPressed: controller.toggleShuffle,
                ),
              ),
              // Prev
              IconButton(
                padding: EdgeInsets.zero,
                constraints: box(m.skipBox),
                icon: Icon(Icons.skip_previous_rounded,
                    size: m.skipIcon, color: Colors.white),
                onPressed: () => controller.playPrevious(),
              ),
              // Play/Pause — scale transition (no rotation)
              Selector<PlaybackController, bool>(
                selector: (_, c) => c.isPlaying,
                builder: (_, isPlaying, __) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.togglePlayPause,
                  
                  child: SizedBox(
                    width: m.playBox,
                    height: m.rowHeight,
                    // The glyph's em box is taller than the visible triangle;
                    // let it overflow the (glyph-sized) row so the empty
                    // quarters above/below do not add vertical spacing.
                    child: OverflowBox(
                      alignment: Alignment.center,
                      minHeight: 0,
                      maxHeight: m.playIcon,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 100),
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(scale: animation, child: child);
                        },
                        child: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(isPlaying),
                          size: m.playIcon,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                ),
              ),
              // Next
              IconButton(
                padding: EdgeInsets.zero,
                constraints: box(m.skipBox),
                icon: Icon(Icons.skip_next_rounded,
                    size: m.skipIcon, color: Colors.white),
                onPressed: () => controller.playNext(),
              ),
              // Loop
              Selector<PlaybackController, LoopMode>(
                selector: (_, c) => c.loopMode,
                builder: (_, loopMode, __) => IconButton(
                  padding: EdgeInsets.zero,
                  constraints: box(m.shuffleBox),
                  icon: Icon(
                    loopMode == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    color: loopMode != LoopMode.off
                        ? AppColors.primaryEnd
                        : Colors.white54,
                    size: m.shuffleIcon,
                  ),
                  onPressed: controller.toggleLoop,
                ),
              ),
            
            ],
          ),
        );
  }
}

// ── Lower Actions (Device Output + Queue) ───────────────────────────────────


class _LowerActions extends StatelessWidget {
  const _LowerActions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Device output (placeholder)
          IconButton(
            icon: const Icon(Icons.cast_rounded,
                size: PlayerControlMetrics.castIcon, color: Colors.white38),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Coming soon'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          // Queue button
          IconButton(
            icon: const Icon(Icons.queue_music_rounded,
                size: PlayerControlMetrics.queueIcon, color: Colors.white38),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}
