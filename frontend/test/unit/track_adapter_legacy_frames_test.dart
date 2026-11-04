// test/unit/track_adapter_legacy_frames_test.dart
//
// Regression: Track records written by builds before Phase 3.1 (July 2026)
// carry only fields 0..9. `isExplicit` (field 10) was added as a NON-nullable
// bool, and the generated adapter cast `fields[10] as bool`, so decoding any
// legacy record threw a TypeError. Hive decodes every frame of a non-lazy box
// while opening it, `liked_tracks` is the first box `HiveStorage.init` opens,
// and `main()` turns that throw into `StartupPhase.fatalStartupError`
// ("Couldn't start Paax — some local data on this device couldn't be read").
// Reproduced on Flutter Web (IndexedDB, 9-field frame from the April 2026
// deployment); the same frames exist on any Android install upgraded from a
// pre-3.1 build.
//
// The fix is `@HiveField(10, defaultValue: false)`, whose generated read is
// `fields[10] == null ? false : fields[10] as bool`. These tests feed the real
// adapter hand-built frames at the old and new shapes.

// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:hive/src/registry/type_registry_impl.dart';
import 'package:beaty/domain/entities/track.dart';

/// Builds a raw adapter payload (the bytes `TrackAdapter.write` would produce)
/// containing exactly [fields], in the same layout hive_generator emits:
/// `numOfFields` byte, then `(fieldIndex byte, value)` pairs.
Uint8List _frame(Map<int, dynamic> fields) {
  final w = BinaryWriterImpl(TypeRegistryImpl.nullImpl);
  w.writeByte(fields.length);
  fields.forEach((i, v) {
    w.writeByte(i);
    w.write(v);
  });
  return w.toBytes();
}

Track _read(Uint8List bytes) =>
    TrackAdapter().read(BinaryReaderImpl(bytes, TypeRegistryImpl.nullImpl));

/// Fields 0..9 as every pre-3.1 build stored them.
Map<int, dynamic> _legacyFields() => {
      0: 'trk-1',
      1: 'Title',
      2: 'Artist',
      3: 'alb-1',
      4: 'Album',
      5: 'https://x/art.jpg',
      6: null, // previewUrl
      7: 215, // duration
      8: 'art-1',
      9: [
        {'name': 'Artist', 'id': 'art-1'}
      ],
    };

void main() {
  group('TrackAdapter backward compatibility', () {
    test('decodes a 10-field (fields 0..9) legacy record with isExplicit=false',
        () {
      final t = _read(_frame(_legacyFields()));
      expect(t.id, 'trk-1');
      expect(t.title, 'Title');
      expect(t.artistName, 'Artist');
      expect(t.albumId, 'alb-1');
      expect(t.albumTitle, 'Album');
      expect(t.artworkUrl, 'https://x/art.jpg');
      expect(t.previewUrl, isNull);
      expect(t.duration, 215);
      expect(t.artistId, 'art-1');
      expect(t.artists, [
        {'name': 'Artist', 'id': 'art-1'}
      ]);
      expect(t.isExplicit, isFalse);
      expect(t.deezerTrackId, isNull);
    });

    test('decodes the 9-field shape observed in the production IndexedDB record',
        () {
      // The April 2026 web deployment wrote 9 fields (no `artists` list).
      final f = _legacyFields()..remove(9);
      final t = _read(_frame(f));
      expect(t.artists, isNull);
      expect(t.isExplicit, isFalse);
      expect(t.deezerTrackId, isNull);
      expect(t.displayArtist, 'Artist');
    });

    test('a record with isExplicit explicitly stored keeps its value', () {
      final f = _legacyFields()
        ..[10] = true
        ..[11] = 'dz-99';
      final t = _read(_frame(f));
      expect(t.isExplicit, isTrue);
      expect(t.deezerTrackId, 'dz-99');
    });

    test('write → read round-trip is unchanged for current records', () {
      final src = Track(
        id: 'trk-2',
        title: 'T2',
        artistName: 'A2',
        albumId: 'alb-2',
        albumTitle: 'Alb2',
        artworkUrl: 'https://x/2.jpg',
        duration: 10,
        isExplicit: true,
        deezerTrackId: 'dz-2',
      );
      final w = BinaryWriterImpl(TypeRegistryImpl.nullImpl);
      TrackAdapter().write(w, src);
      final t = _read(w.toBytes());
      expect(t.id, 'trk-2');
      expect(t.isExplicit, isTrue);
      expect(t.deezerTrackId, 'dz-2');
    });
  });
}
