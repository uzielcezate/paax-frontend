import 'package:flutter/material.dart';
import 'paax_pill.dart';

/// Library filter tabs (Liked / Playlists / Albums / Artists) as sculpted
/// pills (UI Visual System V2 §6). Same 56dp preferred height, order,
/// horizontal scrolling and content-based sizing as before; side padding is
/// the shared floating inset (V3 §2).
class LibraryChipTabs extends StatelessWidget implements PreferredSizeWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final List<String> tabs;

  const LibraryChipTabs({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.tabs,
  });

  static const double pillHeight = 36;

  @override
  Size get preferredSize => const Size.fromHeight(56.0);

  @override
  Widget build(BuildContext context) {
    // 36dp pills + 8dp shadow room inside PaaxSegmentedPills + 6dp above and
    // below = 56dp, matching the previous row exactly.
    return SizedBox(
      height: 56.0,
      child: Center(
        child: PaaxSegmentedPills(
          labels: tabs,
          selectedIndex: selectedIndex,
          onSelected: onTabSelected,
          height: pillHeight,
          gap: 10,
          padding: EdgeInsets.symmetric(
              horizontal: PaaxLayout.floatingInset(context)),
        ),
      ),
    );
  }
}

class SearchSortHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSortPressed;
  final String currentSort;
  final Color? foregroundColor;

  SearchSortHeaderDelegate({
    required this.onSearchChanged,
    required this.onSortPressed,
    required this.currentSort,
    this.foregroundColor,
  });

  @override
  double get minExtent => 64.0;

  @override
  double get maxExtent => 64.0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _SearchSortRow(
      onSearchChanged: onSearchChanged,
      onSortPressed: onSortPressed,
      foregroundColor: foregroundColor,
    );
  }

  @override
  bool shouldRebuild(SearchSortHeaderDelegate oldDelegate) {
    return oldDelegate.currentSort != currentSort;
  }
}

class SearchSortHeader extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSortPressed;
  final String currentSort;
  final Color? foregroundColor;

  const SearchSortHeader({
    super.key,
    required this.onSearchChanged,
    required this.onSortPressed,
    required this.currentSort,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return _SearchSortRow(
      onSearchChanged: onSearchChanged,
      onSortPressed: onSortPressed,
      foregroundColor: foregroundColor,
    );
  }
}

/// Shared layout for search pill + sort pill (UI Visual System V2 §7).
/// Same 44dp controls, 16dp side padding and 10dp gap as before; the
/// [TextField] (focus, keyboard, filtering) is untouched.
class _SearchSortRow extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSortPressed;
  final Color? foregroundColor;

  const _SearchSortRow({
    required this.onSearchChanged,
    required this.onSortPressed,
    this.foregroundColor,
  });

  static const double controlHeight = 44;

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? Colors.white;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: PaaxLayout.floatingInset(context), vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Sort button — sculpted disc, 48dp tap target
          PaaxIconPill(
            icon: Icons.sort_rounded,
            size: controlHeight,
            iconSize: 20,
            minTapSize: controlHeight,
            foregroundColor: fg.withValues(alpha: 0.7),
            semanticLabel: 'Sort',
            onTap: onSortPressed,
          ),
          const SizedBox(width: 10),
          // Search field — sculpted pill shell around the unchanged TextField
          Expanded(
            child: PaaxSearchPill(
              height: controlHeight,
              child: TextField(
                onChanged: onSearchChanged,
                style: TextStyle(color: fg),
                decoration: const InputDecoration(
                  hintText: "Search...",
                  hintStyle: TextStyle(color: PaaxPillTheme.placeholder),
                  prefixIcon:
                      Icon(Icons.search, color: PaaxPillTheme.placeholder),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
