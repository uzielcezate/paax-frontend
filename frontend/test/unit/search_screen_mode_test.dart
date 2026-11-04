// test/unit/search_screen_mode_test.dart — V3 §8.2 dedicated search mode.
//
// Contract: focusing the field enters search mode (genre grid / Browse All /
// pills hidden until there is a query; back pill becomes X); the X restores
// the default browse screen. Header height follows the pill row visibility so
// the pinned header and the scroll spacer never disagree.

import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/presentation/screens/search_screen.dart';
import 'package:beaty/presentation/widgets/paax_pill.dart';
import 'package:beaty/presentation/screens/artist_discography_screen.dart'
    show kDiscographyHeaderBelowStatus, kDiscographyFadePlateau;
import 'package:beaty/core/utils/library_layout.dart';

void main() {
  group('SearchScreenMode', () {
    test('default browse state: no focus, no text', () {
      expect(SearchScreenMode.isSearchMode(hasFocus: false, hasText: false),
          isFalse);
      expect(
          SearchScreenMode.showFilterPills(searchMode: false, hasText: false),
          isTrue);
    });

    test('tapping the field (focus) enters search mode and hides the pills',
        () {
      final mode =
          SearchScreenMode.isSearchMode(hasFocus: true, hasText: false);
      expect(mode, isTrue);
      expect(SearchScreenMode.showFilterPills(searchMode: mode, hasText: false),
          isFalse);
    });

    test(
        'typing a query keeps search mode and brings the pills back (results flow)',
        () {
      final mode = SearchScreenMode.isSearchMode(hasFocus: true, hasText: true);
      expect(mode, isTrue);
      expect(SearchScreenMode.showFilterPills(searchMode: mode, hasText: true),
          isTrue);
    });

    test('losing focus with a query (tapping a result) stays in search mode',
        () {
      expect(SearchScreenMode.isSearchMode(hasFocus: false, hasText: true),
          isTrue);
    });

    test('X restores the default state: unfocused + cleared → browse', () {
      // _exitSearchMode unfocuses and clears the controller; the derived state
      // must then be the default browse screen with pills visible.
      final mode =
          SearchScreenMode.isSearchMode(hasFocus: false, hasText: false);
      expect(mode, isFalse);
      expect(SearchScreenMode.showFilterPills(searchMode: mode, hasText: false),
          isTrue);
    });

    test('header height: 44dp row, pills row only when shown', () {
      const top = 24.0;
      final withPills =
          SearchScreenMode.headerHeight(topPadding: top, showPills: true);
      final noPills =
          SearchScreenMode.headerHeight(topPadding: top, showPills: false);
      expect(withPills, top + 8 + 44 + 10 + 42 + 4);
      expect(noPills, top + 8 + 44 + 4);
      expect(SearchScreenMode.rowHeight, PaaxLayout.topBarPill);
      // Fade plateau ends at the pill row centre, above the header's bottom.
      expect(SearchScreenMode.plateauLift, 4 + 21);
      expect(withPills - SearchScreenMode.plateauLift, lessThan(withPills));
    });
  });

  group('Sticky header fade geometry', () {
    test(
        'Discography: spacer covers the whole pinned header; plateau at pill centre',
        () {
      expect(kDiscographyHeaderBelowStatus, 58 + 34 + 8 + 4);
      expect(kDiscographyFadePlateau, 58 + 21);
      expect(kDiscographyFadePlateau, lessThan(kDiscographyHeaderBelowStatus));
    });

    test('Library: plateau lift reaches the search row centre', () {
      expect(LibraryLayout.fadePlateauLift, 6 + 22);
      // The fade tail extends well below the lowest sticky control.
      expect(PaaxLayout.topFadeTail,
          greaterThanOrEqualTo(LibraryLayout.fadePlateauLift * 2));
    });
  });
}
