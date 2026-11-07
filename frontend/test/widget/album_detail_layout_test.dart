// Regression test: album detail header geometry on wide viewports.
//
// The header used to be sized from the full screen width (blurred square of
// `width` px; cover/gap computed from `width * 0.54` while the rendered cover is
// clamped to 240). On desktop-width Web windows that pushed the title, action
// buttons and track list far below the fold, so album pages looked empty.
//
// Uses the single-track mode of the screen (no network) and measures real
// widget positions at representative viewport sizes.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'package:beaty/core/playback/playback_engine.dart';
import 'package:beaty/data/local/hive_storage.dart';
import 'package:beaty/domain/entities/artist.dart';
import 'package:beaty/domain/entities/genre.dart';
import 'package:beaty/domain/entities/playlist.dart';
import 'package:beaty/domain/entities/saved_album.dart';
import 'package:beaty/domain/entities/single_track_album_detail.dart';
import 'package:beaty/domain/entities/track.dart';
import 'package:beaty/domain/entities/user_profile.dart';
import 'package:beaty/presentation/screens/album_detail_screen.dart';
import 'package:beaty/presentation/state/library_controller.dart';
import 'package:beaty/presentation/state/playback_controller.dart';
import 'package:beaty/presentation/widgets/track_list_tile.dart';

class _FakeEngine implements PlaybackEngine {
  @override
  Stream<int> get playerStateStream => const Stream.empty();
  @override
  Stream<int> get errorStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<void> get completionStream => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(String videoId) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  void prefetchNext(String videoId) {}
  @override
  void dispose() {}
  @override
  Widget buildPlayerView(BuildContext context) => const SizedBox();
}

SingleTrackAlbumDetail _album(String title) {
  final track = Track(
    id: 'vid-$title',
    title: '$title (track)',
    artistName: 'Daft Punk',
    albumId: '1',
    albumTitle: title,
    artworkUrl: '',
    duration: 200,
  );
  return SingleTrackAlbumDetail(
    track: track,
    title: title,
    artistName: 'Daft Punk',
    artworkUrl: '',
    duration: 200,
    releaseYear: 1997,
  );
}

class _Probe {
  _Probe(this.titleTop, this.shuffleTop, this.playTop, this.tileTop);
  final double titleTop;
  final double shuffleTop;
  final double playTop;
  final double tileTop;
}

Future<_Probe> _pump(WidgetTester tester, Size size, String title) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final pc = PlaybackController(engine: _FakeEngine());
  await pc.initialized;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaybackController>.value(value: pc),
      ChangeNotifierProvider<LibraryController>(
          create: (_) => LibraryController()),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: AlbumDetailScreen(singleDetail: _album(title)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull,
      reason: 'no layout/overflow exception at $size');

  // The top bar also carries the title (faded in on scroll); the header title
  // is the lower of the two.
  final titleF = find.text(title);
  expect(titleF, findsAtLeastNWidgets(1), reason: 'title is built at $size');
  var titleTop = double.negativeInfinity;
  for (var i = 0; i < titleF.evaluate().length; i++) {
    final dy = tester.getTopLeft(titleF.at(i)).dy;
    if (dy > titleTop) titleTop = dy;
  }
  final shuffle = find.byIcon(Icons.shuffle_rounded);
  final play = find.byIcon(Icons.play_arrow_rounded);
  final tile = find.byType(TrackListTile);
  return _Probe(
    titleTop,
    shuffle.evaluate().isEmpty ? double.nan : tester.getTopLeft(shuffle).dy,
    play.evaluate().isEmpty ? double.nan : tester.getTopLeft(play).dy,
    tile.evaluate().isEmpty ? double.nan : tester.getTopLeft(tile.first).dy,
  );
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('paax_album_layout_');
    Hive.init(tmp.path);
    Hive.registerAdapter(TrackAdapter());
    Hive.registerAdapter(PlaylistAdapter());
    Hive.registerAdapter(SavedAlbumAdapter());
    Hive.registerAdapter(UserProfileAdapter());
    Hive.registerAdapter(ArtistAdapter());
    Hive.registerAdapter(GenreAdapter());
    await Hive.openBox<Track>(HiveStorage.likedTracksBox);
    await Hive.openBox<Playlist>(HiveStorage.playlistsBox);
    await Hive.openBox<SavedAlbum>(HiveStorage.savedAlbumsBox);
    await Hive.openBox<UserProfile>(HiveStorage.userBox);
    await Hive.openBox<Artist>(HiveStorage.followedArtistsBox);
    await Hive.openBox<Genre>(HiveStorage.followedGenresBox);
    await Hive.openBox(HiveStorage.settingsBox);
    await Hive.openBox<String>(HiveStorage.recentSearchesBox);
    await Hive.openBox<Track>(HiveStorage.recentlyPlayedBox);
    await Hive.openBox(HiveStorage.streamCandidatesBox);
    await Hive.openBox(HiveStorage.playlistOpsBox);
    await Hive.openBox(HiveStorage.profileBootstrapBox);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const sizes = <String, Size>{
    '360dp': Size(360, 800),
    '411dp': Size(411, 891),
    '768dp': Size(768, 1024),
    '1280px': Size(1280, 720),
    '1440px': Size(1440, 900),
    '1920px': Size(1920, 1080),
  };
  const albums = ['Homework', "Burnin'", 'Daft Club'];

  // Header/button/track positions measured on the ORIGINAL layout for phones
  // (<= 444 dp wide the geometry must stay pixel-identical).
  const legacyPhone = <String, List<double>>{
    // title, shuffle, play, first tile
    '360dp': [288, 394, 391, 450],
    '411dp': [339, 445, 442, 501],
  };

  for (final e in sizes.entries) {
    for (final a in albums) {
      testWidgets('album "$a" at ${e.key}: header, buttons and tracks visible',
          (tester) async {
        final size = e.value;
        final p = await _pump(tester, size, a);

        // Not loading, not an error: content is built AND inside the viewport.
        expect(p.titleTop, lessThan(size.height), reason: 'title on screen');
        expect(p.shuffleTop, lessThan(size.height), reason: 'buttons on screen');
        expect(p.playTop, lessThan(size.height), reason: 'play on screen');
        expect(p.tileTop.isNaN, isFalse, reason: 'first track row is built');
        expect(p.tileTop, lessThan(size.height), reason: 'track on screen');
        // Metadata line (year • songs • duration) is part of the header.
        expect(find.textContaining('1997'), findsWidgets);
        // Action buttons exist.
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
        expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsOneWidget);

        final legacy = legacyPhone[e.key];
        if (legacy != null) {
          expect(p.titleTop, closeTo(legacy[0], 0.5));
          expect(p.shuffleTop, closeTo(legacy[1], 0.5));
          expect(p.playTop, closeTo(legacy[2], 0.5));
          expect(p.tileTop, closeTo(legacy[3], 0.5));
        } else {
          // Wide viewports: compact, width-independent header.
          expect(p.titleTop, closeTo(408, 0.5));
          expect(p.tileTop, closeTo(570, 0.5));
        }
      });
    }
  }

  testWidgets('wide viewports give the same header as 768 dp (width-independent)',
      (tester) async {
    final a = await _pump(tester, const Size(768, 1024), 'Homework');
    final b = await _pump(tester, const Size(1920, 1080), 'Homework');
    expect(b.titleTop, closeTo(a.titleTop, 0.5));
    expect(b.shuffleTop, closeTo(a.shuffleTop, 0.5));
    expect(b.tileTop, closeTo(a.tileTop, 0.5));
  });

  testWidgets('scrolling still works (short viewport)', (tester) async {
    final p = await _pump(tester, const Size(360, 480), 'Homework');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    var titleTop = double.negativeInfinity;
    final f = find.text('Homework');
    for (var i = 0; i < f.evaluate().length; i++) {
      final dy = tester.getTopLeft(f.at(i)).dy;
      if (dy > titleTop) titleTop = dy;
    }
    expect(titleTop, lessThan(p.titleTop - 100),
        reason: 'content moved up after scrolling');
  });
}