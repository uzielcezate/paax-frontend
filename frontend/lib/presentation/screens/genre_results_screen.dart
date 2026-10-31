import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/error_state_widget.dart';
import '../../domain/repositories/music_repository.dart';
import '../../data/repositories/music_repository_impl.dart';
import '../../domain/entities/track.dart';
import '../../domain/entities/saved_album.dart';
import '../../domain/entities/artist.dart';
import '../../domain/entities/genre.dart';
import '../state/playback_controller.dart';
import '../state/library_controller.dart';

import '../widgets/music_card.dart';
import '../widgets/track_list_tile.dart';
import '../widgets/bottom_content_padding.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/network_image_with_fallback.dart';
import '../../core/utils/string_utils.dart';
import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import '../widgets/paax_top_bar.dart';
import '../../core/utils/dominant_color_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/thumbnail_prefetcher.dart';

class GenreResultsScreen extends StatefulWidget {
  final String genreSlug;
  final List<Color> gradientColors;

  const GenreResultsScreen({
    super.key,
    required this.genreSlug,
    required this.gradientColors,
  });

  @override
  State<GenreResultsScreen> createState() => _GenreResultsScreenState();
}

class _GenreResultsScreenState extends State<GenreResultsScreen> {
  final MusicRepository _repository = MusicRepositoryImpl();
  
  List<Track> _tracks = [];
  List<SavedAlbum> _albums = [];
  List<Artist> _artists = [];
  
  bool _isLoading = true;
  String? _error;
  bool _songsExpanded = false; // Track if "See all" is pressed
  late ScrollController _scrollController;
  bool _showTitle = false;
  ThumbnailPrefetcher? _prefetcher;

  // Phase 3.2.4 — followable genre resolved from the Supabase catalog by slug.
  // Null until resolved (or when the slug has no matching catalog genre, in
  // which case the Follow control stays hidden).
  String? _genreDeezerId;
  String? _genreUuid;
  String? _genreName;
  String? _genreImage;
  bool get _canFollow =>
      _genreDeezerId != null && _genreDeezerId!.isNotEmpty;

  // Dynamic color from genre gradient
  Color get _dominantColor => widget.gradientColors.first;
  Color get _foregroundColor => Colors.white;

  @override
  void initState() {
    super.initState();
    _prefetcher = ThumbnailPrefetcher(context);

    _scrollController = ScrollController();
    _scrollController.addListener(() {
      // Threshold: when collapsed enough that title should show
      final showTitle = _scrollController.hasClients && _scrollController.offset > 120;
      if (showTitle != _showTitle) {
        setState(() => _showTitle = showTitle);
      }
      
      // Prefetching
      if (!_isLoading && _tracks.isNotEmpty) {
         final urls = [
           ..._tracks.map((t) => t.artworkUrl),
           ..._albums.map((a) => a.artworkUrl),
           ..._artists.map((a) => a.picture),
         ].where((u) => u.isNotEmpty).toList();
         
         _prefetcher?.onScroll(
           controller: _scrollController,
           imageUrls: urls,
           itemExtent: 80, // Avg item height
           buffer: 10,
         );
      }
    });
    _fetchGenreContent();
    _resolveGenre();
  }

  /// Best-effort match of the display slug to a Supabase catalog genre so the
  /// user can follow it. If nothing matches (or it has no Deezer id) the Follow
  /// control simply stays hidden. Never throws.
  Future<void> _resolveGenre() async {
    try {
      const cols = 'id, deezer_id, name, image_cached_url, image_original_url';
      final client = Supabase.instance.client;
      // Prefer an EXACT (case-insensitive) name match so we never bind the
      // Follow control to a different genre that merely contains the slug as a
      // substring. Fall back to a deterministic (name-ordered) substring match.
      Map<String, dynamic>? row = await client
          .from('genres')
          .select(cols)
          .ilike('name', widget.genreSlug)
          .limit(1)
          .maybeSingle();
      row ??= await client
          .from('genres')
          .select(cols)
          .ilike('name', '%${widget.genreSlug}%')
          .order('name')
          .limit(1)
          .maybeSingle();
      if (!mounted || row == null) return;
      final r = row; // final + non-null so promotion holds inside setState
      final deezerId = r['deezer_id']?.toString();
      final cached = r['image_cached_url']?.toString();
      final original = r['image_original_url']?.toString();
      setState(() {
        _genreUuid = r['id']?.toString();
        _genreDeezerId = (deezerId != null && deezerId.isNotEmpty) ? deezerId : null;
        _genreName = r['name']?.toString() ?? widget.genreSlug;
        _genreImage = (cached != null && cached.isNotEmpty) ? cached : original;
      });
    } catch (_) {
      // Non-fatal — the Follow control stays hidden if resolution fails.
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _prefetcher?.dispose();
    super.dispose();
  }

  Future<void> _fetchGenreContent() async {
    try {
      setState(() { _isLoading = true; _error = null; });
      
      // Use search-based approach to get songs, albums, artists for this genre
      final results = await Future.wait([
        _repository.searchTracks('${widget.genreSlug} top songs'),
        _repository.searchAlbums('${widget.genreSlug} top albums'),
        _repository.searchArtists('${widget.genreSlug} music'),
      ]);

      setState(() {
        // Take up to 50 tracks, 10 albums, 10 artists
        _tracks = (results[0] as List<Track>).take(50).toList();
        _albums = (results[1] as List<SavedAlbum>)
            .where((a) => !isPlaceholderArtist(a.artistName))
            .take(10)
            .toList();
        _artists = (results[2] as List<Artist>)
            .where((a) => !isPlaceholderArtist(a.name))
            .take(10)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildSliverAppBar(),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: ErrorStateWidget(
                    rawError: _error,
                    foregroundColor: _foregroundColor,
                    onRetry: _fetchGenreContent,
                  ),
                )
              else ...[
                // === TOP SONGS HEADER ===
                if (_tracks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Top Songs", style: TextStyle(color: _foregroundColor, fontSize: 20, fontWeight: FontWeight.w800)),
                          TextButton.icon(
                            onPressed: _showAddToPlaylistSheet,
                            icon: Icon(Icons.playlist_add, color: _foregroundColor, size: 20),
                            label: Text("Add all", style: TextStyle(color: _foregroundColor, fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),

                // === TOP SONGS LIST (Lazy) ===
                if (_tracks.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = _tracks[index];
                        // If collapsed, only show first 5
                        if (!_songsExpanded && index >= 5) return null;
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: TrackListTile(
                            track: track,
                            index: index + 1,
                            showArtwork: true,
                            foregroundColor: _foregroundColor,
                            allowSwipeActions: true,
                            onTap: () => context.read<PlaybackController>().playQueue(_tracks, index: index),
                          ),
                        );
                      },
                      childCount: _songsExpanded ? _tracks.length : 5.clamp(0, _tracks.length),
                    ),
                  ),
              
                // === EXPAND BUTTON ===
                if (_tracks.length > 5)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      child: Center(
                        child: GestureDetector(
                          onTap: () => setState(() => _songsExpanded = !_songsExpanded),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: _foregroundColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _foregroundColor.withOpacity(0.2), width: 0.5),
                            ),
                            child: Text(
                              _songsExpanded ? "Show less" : "See all ${_tracks.length} songs",
                              style: TextStyle(
                                color: _foregroundColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 6)),

                // === TOP ALBUMS ===
                if (_albums.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader("Top Albums"),
                        _buildAlbumsCarousel(),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),

                // === TOP ARTISTS ===
                if (_artists.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader("Top Artists"),
                        _buildArtistsCarousel(),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  
                const SliverToBoxAdapter(child: BottomContentPadding()),
              ],
            ],
          ),


          // Bottom fade
          // (V4 §1) bottom fade is painted once by the MainWrapper dock.

          // ── Local top navigation bar (sculpted pills) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PaaxTopBar(
              title: widget.genreSlug,
              showTitle: _showTitle,
              onBack: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final expandedHeight = Responsive.value(context, mobile: 240.0, tablet: 260.0, desktop: 280.0);

    return SliverAppBar(
      pinned: true,
      expandedHeight: expandedHeight,
      backgroundColor: Colors.transparent,
      forceMaterialTransparency: true,
      elevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 0,
      leading: const SizedBox.shrink(),
      titleSpacing: 0,
      title: null,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(_dominantColor, Colors.black, 0.82) ?? const Color(0xFF181818),
                AppColors.background,
              ],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                bottom: 16,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.music_note_rounded, size: 64, color: _foregroundColor.withOpacity(0.85)),
                    const SizedBox(height: 8),
                    Text(
                      widget.genreSlug,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: _foregroundColor,
                        height: 1.1,
                      ),
                    ),
                    if (_canFollow) ...[
                      const SizedBox(height: 12),
                      _buildFollowButton(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Follow / Following pill for the resolved catalog genre. Uses the existing
  /// LibraryController.toggleFollowGenre; the followed state syncs to Supabase +
  /// Hive via the offline-first library pipeline.
  Widget _buildFollowButton() {
    return Consumer<LibraryController>(
      builder: (context, library, _) {
        final following = library.isGenreFollowed(_genreDeezerId ?? '');
        return GestureDetector(
          onTap: () {
            library.toggleFollowGenre(Genre(
              id: _genreDeezerId!,
              name: _genreName ?? widget.genreSlug,
              imageUrl: _genreImage,
              slug: widget.genreSlug,
              supabaseId: _genreUuid,
            ));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: following
                  ? _foregroundColor.withOpacity(0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _foregroundColor.withOpacity(0.55), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(following ? Icons.check_rounded : Icons.add_rounded,
                    color: _foregroundColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  following ? "Following" : "Follow",
                  style: TextStyle(
                    color: _foregroundColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(title, style: TextStyle(color: _foregroundColor, fontSize: 20, fontWeight: FontWeight.w800)),
    );
  }

  void _showAddToPlaylistSheet() {
    final songsToAdd = _songsExpanded ? _tracks : _tracks.take(5).toList();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddToPlaylistSheet(tracks: songsToAdd),
    );
  }

  // === TOP ALBUMS CAROUSEL (10 items) ===
  Widget _buildAlbumsCarousel() {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 16),
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        primary: false,
        itemCount: _albums.length,
        itemBuilder: (context, index) {
          final album = _albums[index];
          return MusicCard(
            title: album.title,
            subtitle: album.artistName,
            imageUrl: album.artworkUrl,
            foregroundColor: _foregroundColor,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)));
            },
          );
        },
      ),
    );
  }

  // === TOP ARTISTS CAROUSEL (10 items) ===
  Widget _buildArtistsCarousel() {
    return SizedBox(
      height: 160,
      child: ListView.builder(
        padding: const EdgeInsets.only(left: 16),
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        primary: false,
        itemCount: _artists.length,
        itemBuilder: (context, index) {
          final artist = _artists[index];
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistDetailScreen(
                  artistId: artist.id,
                  artistName: artist.name,
                  pictureUrl: artist.picture,
                )));
              },
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceLight,
                    ),
                    child: ClipOval(
                      child: NetworkImageWithFallback(
                        imageUrl: artist.picture,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 100,
                    child: Text(
                      artist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _foregroundColor, fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
