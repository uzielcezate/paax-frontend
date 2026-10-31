// Replace the old SearchScreen implementation with the new UI
import 'package:flutter/material.dart';
import 'main_wrapper.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/error_state_widget.dart';
import '../../domain/entities/track.dart';
import '../../domain/entities/saved_album.dart';
import '../../domain/entities/artist.dart';
import '../state/search_controller.dart' as app_search;
import '../state/playback_controller.dart';
import 'artist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'track_detail_screen.dart';
import '../widgets/track_list_tile.dart';
import '../widgets/music_card.dart';
import '../widgets/thumbnail.dart';
import '../widgets/app_image.dart';
import '../../core/image/lh3_url_builder.dart';

import '../widgets/bottom_content_padding.dart';
import '../widgets/glass_surface.dart';
import '../widgets/genre_card.dart';
import '../widgets/paax_pill.dart';
import '../widgets/paax_top_bar.dart';
import 'genre_results_screen.dart';

import '../../core/utils/responsive.dart';

 class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocus = FocusNode();
  // ValueNotifier for clear-button visibility — avoids full setState on every keystroke
  late final ValueNotifier<bool> _hasText;
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);
  String _selectedFilter = 'All';

  // V3 §8.2 — dedicated search-input mode. Entered when the field gains focus
  // (or already holds a query); left via the X pill, which restores the
  // default browse screen. Pure so it is unit-testable.
  bool _searchMode = false;

  @override
  void initState() {
    super.initState();
    _hasText = ValueNotifier(_textController.text.isNotEmpty);
    _textController.addListener(() {
      _hasText.value = _textController.text.isNotEmpty;
      _syncSearchMode();
    });
    _searchFocus.addListener(_syncSearchMode);
    _scrollController.addListener(() {
      _scrollOffset.value = _scrollController.offset;
    });
  }

  void _syncSearchMode() {
    final next = SearchScreenMode.isSearchMode(
      hasFocus: _searchFocus.hasFocus,
      hasText: _textController.text.isNotEmpty,
    );
    if (next != _searchMode && mounted) setState(() => _searchMode = next);
  }

  /// X pill: leave search mode and restore the default browse screen without
  /// navigating away from the Search tab.
  void _exitSearchMode(app_search.SearchController search) {
    _searchFocus.unfocus();
    _textController.clear();
    search.onQueryChanged("");
    setState(() {
      _selectedFilter = 'All';
      _searchMode = false;
    });
  }

  @override
  void dispose() {
    _hasText.dispose();
    _textController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<app_search.SearchController>();
    final double topPadding = MediaQuery.of(context).padding.top;
    final double inset = PaaxLayout.floatingInset(context);
    final bool showPills = SearchScreenMode.showFilterPills(
      searchMode: _searchMode,
      hasText: _textController.text.isNotEmpty,
    );

    // Header: status bar + 8 + back/search row (44) + [10 + pills (34 + 8
    // shadow room)] + 4. The pinned header and the scroll spacer share it.
    final double headerHeight = SearchScreenMode.headerHeight(
      topPadding: topPadding,
      showPills: showPills,
    );
    // Fade plateau ends at the vertical centre of the lowest pinned control.
    final double fadePlateau = headerHeight - SearchScreenMode.plateauLift;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                 SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                 ..._buildBodySlivers(search),
              ],
            ),
          ),
          // (V4 §1) The bottom fade is painted once by the MainWrapper dock;
          // no per-screen bottom gradient here, so nothing stacks.
          // Pinned top controls over one atmospheric fade (V3 §4/§5): no
          // opaque rectangle — the fade plateaus behind the controls and
          // dissolves below the lowest pill, following scroll.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _scrollOffset,
                  builder: (_, offset, __) => PaaxHeaderFade(
                    plateau: fadePlateau,
                    opacity: (offset / 40.0).clamp(0.0, 1.0),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: topPadding + 8, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Back / X pill + Search pill (top row), both
                      // 44dp tall, outer edges on the shared inset.
                      Padding(
                        padding: EdgeInsets.only(right: inset),
                        child: SizedBox(
                          height: PaaxLayout.topBarPill,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                    left: PaaxTopBar.controlOffset(inset)),
                                child: _searchMode
                                    ? PaaxIconPill(
                                        key: const Key('search_close'),
                                        icon: Icons.close_rounded,
                                        iconSize: 22,
                                        semanticLabel: 'Close search',
                                        onTap: () => _exitSearchMode(search),
                                      )
                                    : PaaxIconPill(
                                        key: const Key('search_back'),
                                        icon: Icons.arrow_back_ios_new_rounded,
                                        iconSize: PaaxTopBar.backIconSize,
                                        semanticLabel: 'Back',
                                        onTap: () {
                                          final mainWrapper = MainWrapper.shellKey.currentState;
                                          if (mainWrapper != null) {
                                            mainWrapper.onBackPressed();
                                          } else {
                                            Navigator.maybePop(context);
                                          }
                                        },
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: PaaxSearchPill(
                                  height: PaaxLayout.topBarPill,
                                  child: TextField(
                                    controller: _textController,
                                    focusNode: _searchFocus,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: "What do you want to listen to?",
                                      hintStyle: const TextStyle(color: PaaxPillTheme.placeholder, fontSize: 13),
                                      prefixIcon: const Icon(Icons.search, color: PaaxPillTheme.placeholder, size: 18),
                                      filled: false,
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                      isDense: true,
                                      suffixIcon: ValueListenableBuilder<bool>(
                                        valueListenable: _hasText,
                                        builder: (_, hasText, __) => hasText
                                            ? IconButton(
                                                icon: Icon(Icons.clear, color: Colors.white.withValues(alpha: 0.4), size: 18),
                                                onPressed: () {
                                                  _textController.clear();
                                                  search.onQueryChanged("");
                                                },
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                    onChanged: (val) {
                                      search.onQueryChanged(val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 2. Filter pills (below search bar). Hidden in
                      // search mode until there is a query — the results
                      // flow switches on them.
                      if (showPills) ...[
                        const SizedBox(height: 10),
                        PaaxSegmentedPills(
                          labels: _searchFilters,
                          selectedIndex: _searchFilters.indexOf(_selectedFilter),
                          onSelected: (i) =>
                              setState(() => _selectedFilter = _searchFilters[i]),
                          height: 34,
                          gap: 8,
                          padding: EdgeInsets.only(left: inset, right: 8),
                        ),
                      ],
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

  // ... (Genre Data skipped)
  static const List<String> _searchFilters = ["All", "Tracks", "Albums", "Artists"];

  final List<Map<String, dynamic>> _genres = [
    {"name": "Pop", "colors": [const Color(0xFF8A2387), const Color(0xFFE94057), const Color(0xFFF27121)]},
    {"name": "Rock", "colors": [const Color(0xFF232526), const Color(0xFF414345)]},
    {"name": "Latin", "colors": [const Color(0xFFDA22FF), const Color(0xFF9733EE)]},
    {"name": "Hip Hop", "colors": [const Color(0xFF11998e), const Color(0xFF38ef7d)]},
    {"name": "Electro", "colors": [const Color(0xFF12c2e9), const Color(0xFFc471ed), const Color(0xFFf64f59)]},
    {"name": "Indie", "colors": [const Color(0xFF00b09b), const Color(0xFF96c93d)]},
    {"name": "R&B", "colors": [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)]},
    {"name": "Reggaeton", "colors": [const Color(0xFFFF512F), const Color(0xFFDD2476)]},
    {"name": "K-pop", "colors": [const Color(0xFFf953c6), const Color(0xFFb91d73)]},
    {"name": "Jazz", "colors": [const Color(0xFFFDC830), const Color(0xFFF37335)]},
    {"name": "Classical", "colors": [const Color(0xFF4CA1AF), const Color(0xFFC4E0E5)]},
    {"name": "Country", "colors": [const Color(0xFFe65c00), const Color(0xFFF9D423)]},
    {"name": "Metal", "colors": [const Color(0xFF121212), const Color(0xFF434343)]},
    {"name": "Funk", "colors": [const Color(0xFFCC95C0), const Color(0xFFDBD4B4), const Color(0xFF7AA1D2)]},
    {"name": "House", "colors": [const Color(0xFF4568DC), const Color(0xFFB06AB3)]},
    {"name": "Techno", "colors": [const Color(0xFF200122), const Color(0xFF6f0000)]},
    {"name": "Lo-fi", "colors": [const Color(0xFF5f2c82), const Color(0xFF49a09d)]},
    {"name": "Afro", "colors": [const Color(0xFFD38312), const Color(0xFFA83279)]},
    {"name": "Regional", "colors": [const Color(0xFF00416A), const Color(0xFFE4E5E6)]},
  ];

  List<Widget> _buildBodySlivers(app_search.SearchController search) {
    // Phase 3.3.1 §5: show the global spinner ONLY while loading AND there are
    // no usable (cached/partial) results yet — never hide already-available
    // results behind a full-screen spinner. Once any category has painted, the
    // results below stay visible while the rest revalidates.
    final bool hasAnyResults = search.trackResults.isNotEmpty ||
        search.albumResults.isNotEmpty ||
        search.artistResults.isNotEmpty;
    if (search.isLoading && _textController.text.isNotEmpty && !hasAnyResults) {
      return [const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Colors.white)))];
    }

    // Add top padding to content so it doesn't touch the divider immediately
    const topContentPadding = SliverToBoxAdapter(child: SizedBox(height: 12));

    if (_textController.text.isEmpty) {
      if (_searchMode) {
        // Dedicated search-input mode, empty query. Intentionally empty: a
        // future version renders local search history (+ Clear History) here.
        // No storage, no placeholders now (V3 §8.2).
        return const [SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink())];
      }
      return [
         topContentPadding,
         SliverPadding(
           padding: EdgeInsets.symmetric(horizontal: PaaxLayout.floatingInset(context)),
           sliver: SliverToBoxAdapter(
             child: Padding(
               padding: const EdgeInsets.only(bottom: 16),
               child: const Text("Browse All", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
             ),
           ),
         ),
         SliverPadding(
           padding: EdgeInsets.symmetric(horizontal: PaaxLayout.floatingInset(context)),
           sliver: SliverGrid(
             gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
               maxCrossAxisExtent: 200, // Responsive tiles
               childAspectRatio: 1.6,
               crossAxisSpacing: 12,
               mainAxisSpacing: 12,
             ),
             delegate: SliverChildBuilderDelegate(
               (context, index) {
                 final genre = _genres[index];
                   return GenreCard(
                     label: genre['name'],
                     colors: genre['colors'],
                     onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => GenreResultsScreen(
                          genreSlug: genre['name'],
                          gradientColors: genre['colors'],
                        )));
                     },
                   );
               },
               childCount: _genres.length,
             ),
           ),
         ),
         const SliverToBoxAdapter(child: BottomContentPadding()),
      ];
    }
    
    if (search.error != null) {
      return [
        SliverFillRemaining(
          child: ErrorStateWidget(
            rawError: search.error,
            onRetry: () => search.retry(),
          ),
        ),
      ];
    }
    
    final bool hasResults = search.trackResults.isNotEmpty || search.albumResults.isNotEmpty || search.artistResults.isNotEmpty;

    if (!hasResults) {
      return [const SliverFillRemaining(child: Center(child: Text("No results found.", style: TextStyle(color: Colors.grey))))];
    }

    if (_selectedFilter == "All") {
      return [topContentPadding, ..._buildAllResultsSlivers(search)];
    } else if (_selectedFilter == "Tracks") {
      return [topContentPadding, ..._buildTracksListSlivers(search.trackResults)];
    } else if (_selectedFilter == "Albums") {
      return [topContentPadding, ..._buildAlbumsGridSlivers(search.albumResults)];
    } else {
      return [topContentPadding, ..._buildArtistsGridSlivers(search.artistResults)];
    }
  }

  // ... (Rest of build methods _buildAllResultsSlivers, etc. remain unchanged)

  List<Widget> _buildAllResultsSlivers(app_search.SearchController search) {
    // Phase 3.3.3 issue 1: the Top Result is the relevance-ranked artist (may be
    // derived from the primary artist of the strongest exact matches, e.g.
    // Shakira for "Dai Dai"). The controller owns the fallback, so the tile only
    // ever shows a resolved artist (no wrong-artist flicker; review M3).
    final topArtist = search.topResult;
    final railArtists = topArtist == null
        ? search.artistResults
        : search.artistResults.where((a) => a.id != topArtist.id).toList();
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            // Top Result (relevance-ranked artist)
            if (topArtist != null) ...[
              const Text("Top Result", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _buildArtistTile(topArtist, large: true),
              const SizedBox(height: 24),
            ],

            // Tracks
            if (search.trackResults.isNotEmpty) ...[
              const Text("Songs", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              // Track tiles use same TrackListTile as Tracks tab â€” identical fit
              ...search.trackResults.take(5).map((t) => _buildTrackTile(t)).toList(),
              if (search.trackResults.length > 5)
                 Align(
                   alignment: Alignment.centerLeft,
                   child: TextButton(
                     child: const Text("See all songs", style: TextStyle(color: Colors.white)), 
                     onPressed: () => setState(() => _selectedFilter = "Tracks")
                   )
                 ),
              const SizedBox(height: 24),
            ],

            // Albums
            if (search.albumResults.isNotEmpty) ...[
              const Text("Albums", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _buildAlbumsRail(search.albumResults.take(5).toList()),
              const SizedBox(height: 24),
            ],
            
            // Artists (excluding the one shown as Top Result)
            if (railArtists.isNotEmpty) ...[
               const Text("Artists", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
               const SizedBox(height: 12),
               _buildArtistsRail(railArtists.take(5).toList()),
            ],
            
            const BottomContentPadding(),
          ]),
        ),
      ),
    ];
  }

  // --- Components ---

  Widget _buildTrackTile(Track track) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: TrackListTile(
         track: track,
         index: 0, 
         showArtwork: true,
         allowSwipeActions: true,
         onTap: () {
            context.read<PlaybackController>().playTrack(track);
         },
      ),
    );
  }
  
  List<Widget> _buildTracksListSlivers(List<Track> tracks) {
    return [
      SliverPadding(
        padding: EdgeInsets.zero,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
               if (i == tracks.length) return const BottomContentPadding();
               return Padding(
                 padding: const EdgeInsets.only(bottom: 2.0),
                 child: TrackListTile(
                  track: tracks[i], 
                  index: i,
                  showArtwork: true,
                  allowSwipeActions: true,
                  onTap: () {
                     context.read<PlaybackController>().playQueue(tracks, index: i);
                  }
                 ),
               );
            },
            childCount: tracks.length + 1,
          ),
        ),
      )
    ];
  }

  Widget _buildArtistTile(Artist artist, {bool large = false}) {
    return GestureDetector(
      onTap: () {
         Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistDetailScreen(
            artistId: artist.id, artistName: artist.name, pictureUrl: artist.picture
         )));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Hero(
                tag: 'artist_${artist.id}',
                // AppImage gives a graceful placeholder instead of a broken/blank
                // avatar when the artist image is missing (§7).
                child: AppImage(
                  url: artist.picture,
                  sizePx: Lh3UrlBuilder.listSize,
                  width: (large ? 40 : 24) * 2,
                  height: (large ? 40 : 24) * 2,
                  isCircular: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white, 
                        fontWeight: FontWeight.w800,
                        fontSize: large ? 20 : 16
                      ),
                    ),
                    const Text("Artist", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtistsRail(List<Artist> artists) {
    // Responsive avatar size
    final avatarRadius = Responsive.value(context, mobile: 50.0, tablet: 60.0, desktop: 70.0);
    // Height: Diameter + Spacing + Text
    final railHeight = (avatarRadius * 2) + 8 + 40;

    return SizedBox(
      height: railHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        primary: false,
        itemCount: artists.length,
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.only(right: Responsive.spacing(context)),
          child: Column(
            children: [
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistDetailScreen(
                   artistId: artists[i].id, artistName: artists[i].name, pictureUrl: artists[i].picture
                ))),
                child: AppImage(
                  url: artists[i].picture,
                  sizePx: Lh3UrlBuilder.listSize,
                  width: avatarRadius * 2,
                  height: avatarRadius * 2,
                  isCircular: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: avatarRadius * 2,
                child: Text(
                  artists[i].name, 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis, 
                  textAlign: TextAlign.center, 
                  style: const TextStyle(color: Colors.white)
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  List<Widget> _buildArtistsGridSlivers(List<Artist> artists) {
    return [
       SliverPadding(
         padding: const EdgeInsets.symmetric(horizontal: 16),
         sliver: SliverGrid(
           gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
             maxCrossAxisExtent: 200, 
             childAspectRatio: 0.8,
             crossAxisSpacing: 16, 
             mainAxisSpacing: 16
           ),
           delegate: SliverChildBuilderDelegate(
             (context, index) {
               final artist = artists[index];
               return GestureDetector(
                 onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistDetailScreen(
                      artistId: artist.id,
                      artistName: artist.name,
                      pictureUrl: artist.picture
                    )));
                 },
                 child: Column(
                   children: [
                     Expanded(
                       child: AspectRatio(
                         aspectRatio: 1,
                         child: AppImage(
                           url: artist.picture,
                           sizePx: Lh3UrlBuilder.listSize,
                           isCircular: true,
                         ),
                       ),
                     ),
                     const SizedBox(height: 12),
                     Text(
                       artist.name, 
                       maxLines: 1, 
                       overflow: TextOverflow.ellipsis, 
                       textAlign: TextAlign.center, 
                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)
                     ),
                   ],
                 ),
               );
             },
             childCount: artists.length,
           ),
         ),
       ),
       const SliverToBoxAdapter(child: BottomContentPadding()),
    ];
  }
  
  Widget _buildAlbumsRail(List<SavedAlbum> albums) {
    final cardWidth = Responsive.value(context, mobile: 140.0, tablet: 160.0, desktop: 200.0);
    final cardHeight = cardWidth + 56; 

    return SizedBox(
      height: cardHeight,
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 0), 
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        primary: false,
        itemCount: albums.length,
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.only(right: Responsive.spacing(context)),
          child: MusicCard(
            width: cardWidth,
            title: albums[i].title,
            subtitle: albums[i].artistName,
            imageUrl: albums[i].artworkUrl,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: albums[i]))),
          ),
        ),
      ),
    );
  }
  
  List<Widget> _buildAlbumsGridSlivers(List<SavedAlbum> albums) {
    return [
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: PaaxLayout.floatingInset(context)),
        sliver: SliverGrid(
           gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
               maxCrossAxisExtent: 200, 
               childAspectRatio: 0.75, 
               crossAxisSpacing: 16, 
               mainAxisSpacing: 16
           ),
           delegate: SliverChildBuilderDelegate(
             (context, index) {
               final album = albums[index];
               return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album))),
                  child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Expanded(child: Thumbnail(
                           url: album.artworkUrl,
                           sizePx: 200,
                           borderRadius: 12,
                           fit: BoxFit.cover,
                         )),
                         const SizedBox(height: 8),
                         Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                         Text(album.artistName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                       ],
                  ),
               );
             },
             childCount: albums.length
           ),
        ),
      ),
      const SliverToBoxAdapter(child: BottomContentPadding()),
    ];
  }
}

/// Pure state/geometry helpers for the Search screen header (V3 §8), kept
/// free of widgets so the focus-mode contract is unit-testable.
class SearchScreenMode {
  SearchScreenMode._();

  /// Search mode is on while the field has focus or already holds a query, so
  /// tapping a result (which drops focus) does not snap back to Browse All.
  static bool isSearchMode({required bool hasFocus, required bool hasText}) =>
      hasFocus || hasText;

  /// Category pills are part of the default browse screen and of the results
  /// flow (they switch All / Tracks / Albums / Artists). They are hidden only
  /// in search mode with an empty query.
  static bool showFilterPills({required bool searchMode, required bool hasText}) =>
      !searchMode || hasText;

  static const double rowTop = 8;
  static const double rowHeight = PaaxLayout.topBarPill; // 44
  static const double pillsGap = 10;
  static const double pillsRow = 34 + PaaxSegmentedPills.shadowRoom; // 42
  static const double bottom = 4;

  /// Distance from the header's bottom edge up to the vertical centre of the
  /// lowest pinned control (pill row centre, or the search row centre).
  static const double plateauLift = bottom + pillsRow / 2;

  static double headerHeight({required double topPadding, required bool showPills}) =>
      topPadding + rowTop + rowHeight + (showPills ? pillsGap + pillsRow : 0) + bottom;
}
