# Components

> **Purpose**: Catalogs the reusable UI components (custom Flutter widgets) — their anatomy, variants, states, and specs. The reference for building and reviewing UI.
> **Update when**: A new shared widget is added, a variant is introduced, or behavior changes.

---

## How components work in Paax

There is no third-party component kit and no Figma. Components are **custom Flutter widgets** under `frontend/lib/presentation/widgets/`, built on Material 3. The visual backbone is the **surface system** in `glass_surface.dart` (solid dark fills + `white@0.08`, 0.5px borders + soft shadows — blur is disabled; see [design-system.md](design-system.md#theme-system)). Most other components compose those surfaces.

Shared surface tokens (`BeatyGlassTokens`, `frontend/lib/presentation/widgets/glass_surface.dart`):

| Token | Value | Meaning |
|-------|-------|---------|
| `radius` | 16.0 | Default surface corner radius |
| `radiusPill` | 24.0 | Pill / chip corner radius |
| `heightCompact` / `heightRegular` | 38 / 44 | Standard control heights |
| `tintOpacity` / `tintOpacityLight` | 0.32 / 0.18 | Fill tint (nominal — fills render solid `#111`) |
| `borderOpacity` / `borderWidth` | 0.08 / 0.5 | The signature glass rim |
| `shadowOpacity` | 0.18 | Soft drop-shadow strength |
| `hPadding` / `vPadding` | 14 / 8 | Default inner padding |
| `highlightOpacity` | 0.06 | Inner-highlight gradient strength |

See the engineering-oriented widget inventory in [frontend/widgets.md](../frontend/widgets.md). This doc is the **design spec** view.

---

## Component Catalog

| Component | File | Variants | Status |
|-----------|------|----------|--------|
| `BeatyGlassSurface` / `GlassSurface` | `presentation/widgets/glass_surface.dart` | border on/off, shadow on/off, custom fill | ✅ Core |
| `GlassPill` | `presentation/widgets/glass_surface.dart` | any height (radius = h/2) | ✅ |
| `GlassChip` | `presentation/widgets/glass_surface.dart` | Selected (white fill), Unselected (dark + rim) | ✅ |
| `GlassCircleButton` / `GlassMenuButton` | `presentation/widgets/glass_surface.dart` | icon / arbitrary child | ✅ |
| `ScrolledTopPill` / `FloatingTopControls` | `presentation/widgets/glass_surface.dart` | default ↔ scrolled (cross-fade) | ✅ |
| `DynamicEdgeFade` | `presentation/widgets/glass_surface.dart` | `.black`, `.dynamic`, `.dynamicBottom` | ✅ Core |
| `black_glass_blur_surface` / `paax_glass_container` | `presentation/widgets/` | solid variants of the glass surface | ✅ |
| `MusicCard` | `presentation/widgets/music_card.dart` | album / artist / playlist tile | ✅ |
| `TrackListTile` | `presentation/widgets/track_list_tile.dart` | default, current (bold+border), hidden (dimmed); swipe actions | ✅ |
| `GenreCard` | `presentation/widgets/genre_card.dart` | colored genre entry (search empty state) | ✅ |
| `PlaylistCover` | `presentation/widgets/playlist_cover.dart` | 1-up / 2×2 collage | ✅ |
| `SectionHeader` | `presentation/widgets/section_header.dart` | title + optional action | ✅ |
| `LibraryChipTabs` / `SearchSortHeader` | `presentation/widgets/library_headers.dart` | chip tab bar / sort+search header | ✅ |
| `AppImage` (+ `Thumbnail`) | `presentation/widgets/app_image.dart`, `thumbnail.dart` | mobile (`CachedNetworkImage`) / web (`Image.network`); music-note placeholder | ✅ Core |
| `MiniPlayer` | `presentation/widgets/mini_player.dart` | shown when a track exists (~67px) | ✅ |
| `QueueBottomSheet` | `presentation/widgets/queue_bottom_sheet.dart` | draggable, reorderable | ✅ |
| `SmoothAudioProgressBar` | `presentation/widgets/smooth_audio_progress_bar.dart` | 60fps interpolated | ✅ |
| `SyncedLyricsView` | `presentation/widgets/synced_lyrics_view.dart` | auto-advance, glow, center-scroll | ✅ |
| `MarqueeText` | `presentation/widgets/marquee_text.dart` | scroll-if-overflow | ✅ |
| `AddToPlaylistSheet` / `OverflowMenu` / `SortBottomSheet` | `presentation/widgets/` | bottom-sheet actions; menu types track/album/artist/playlist | ✅ |
| `ExplicitBadge` | `presentation/widgets/explicit_badge.dart` | "E" marker | ✅ |
| `ErrorStateWidget` | `presentation/widgets/error_state_widget.dart` | classifies error string → icon + retry | ✅ |
| `HiddenVideoPlayer` | `presentation/widgets/hidden_video_player.dart` | 300×300 offscreen WebView host | ✅ (infra) |

> Several image widgets (`network_image_with_fallback`, `smart_network_image`, `queued_network_image`) are **legacy variants** superseded by `AppImage` — prefer `AppImage`/`Thumbnail` in new code. `thumbnail_prefetcher` is **deprecated** (off-screen prefetch caused HTTP 429s).

---

## Component Specs

### `BeatyGlassSurface` (and `GlassSurface`)

**Description**: The base "glass" container. A solid dark rounded rectangle with a hairline rim and soft shadow. Nearly every panel/pill/button composes it. `GlassSurface` is an API-compatible thin wrapper.
**File**: `frontend/lib/presentation/widgets/glass_surface.dart`

#### Anatomy
```
┌───────────────────────────────┐  ← white@0.08, 0.5px rim
│  (child)                       │  ← fill: AppColors.surface (#111)
└───────────────────────────────┘  ← soft shadow: black@0.10, blur 10, y+1
```

#### Props
| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | — | Content |
| `width` / `height` | `double?` | `null` | Optional fixed size |
| `borderRadius` | `BorderRadius` | `radius 16` | Corner radius |
| `showBorder` | `bool` | `true` | White@0.08, 0.5px rim |
| `showShadow` | `bool` | `true` | Soft drop shadow |
| `enableBlur` | `bool` | `true` | **Ignored** — always solid (`forceSolidGlass`) |
| `overrideFill` | `Color?` | `null` | Fill override (else `#111`) |

#### States
| State | Visual |
|-------|--------|
| Default | `#111` fill, `white@0.08` 0.5px rim, soft shadow |
| No border / no shadow | Flat panel (set `showBorder`/`showShadow` false) |
| Blur | **Never** — `enableBlur` is a no-op; see [design-system.md](design-system.md#theme-system) |

---

### `GlassChip`

**Description**: Selectable filter chip. Used for library tabs and search filters.
**File**: `glass_surface.dart`

| State | Visual |
|-------|--------|
| Selected | Fill `white@0.88`, **black** text, `w700`, `fontSize 12.5`, radius 20, padding `H14/V6` |
| Unselected | Fill `AppColors.elevatedSurface` (#111), text `white@0.8`, `white@0.08` 0.5px rim |

> Colors are overridable (`selectedColor`/`unselectedColor`/`textColor`) — used when a screen tints chips with the ambient artwork color.

---

### `GlassPill` / `ScrolledTopPill` / `FloatingTopControls`

**Description**: The floating top-bar system on detail screens. `GlassPill` is a full-radius (`h/2`) surface. `ScrolledTopPill` is a back-button + centered title pill. `FloatingTopControls` cross-fades between the "default" floating controls and the compact `ScrolledTopPill` as the user scrolls.
**File**: `glass_surface.dart`

- Cross-fade: `AnimatedCrossFade`, **60ms**, `Curves.linear` (see [animations.md](animations.md)).
- `ScrolledTopPill` height 40; title `w800`, `fontSize 15`; foreground driven by `foregroundColor` (ambient/adaptive).

---

### `GlassCircleButton` / `GlassMenuButton`

**Description**: Round icon buttons floating over artwork (back, overflow, etc.).
**File**: `glass_surface.dart`

| Prop | Default | Note |
|------|---------|------|
| `size` | 40 | ⚠️ Below the 48px min touch target |
| `iconSize` | 18 | — |
| Fill / rim / shadow | Sculpted pill (`PaaxIconPill`) since V2 — see [Sculpted Pill System](#sculpted-pill-system-ui-visual-system-v2--v3-2026-10-2324) | tap target is now ≥48dp around the 40dp disc |

---

### `TrackListTile`

**Description**: The primary row for a track in lists (library, album, playlist, search).
**File**: `frontend/lib/presentation/widgets/track_list_tile.dart`

| State | Visual |
|-------|--------|
| Default | Thumbnail + title/artist, trailing overflow/action |
| Current (now playing) | **Bold** title + accent border |
| Hidden | Dimmed (reduced opacity) |
| Swipe | Reveals actions — add-to-playlist / add-to-queue (and remove-from-playlist in a playlist context) |

Pairs with `OverflowMenu` (`MenuType.track`) and `AddToPlaylistSheet`.

---

### `DynamicEdgeFade`

**Description**: The gradient overlay that makes content "dissolve" under floating chrome. Central to the cinematic aesthetic.
**File**: `glass_surface.dart`

| Variant | Color | Height | Max opacity | Direction |
|---------|-------|--------|-------------|-----------|
| `.black` | `#121212` (legacy literal) | 130 | 0.95 | top |
| `.dynamic` | caller-supplied (ambient) | 130 | 0.92 | top |
| `.dynamicBottom` | caller-supplied (ambient) | 240 | 0.98 | bottom |

Multi-stop `LinearGradient` (5–6 stops) fading opaque→transparent so scrolling content vanishes gradually beneath the top controls / above the mini-player. `TopFadeGradient` and `EdgeGradient` are **deprecated** wrappers — prefer `DynamicEdgeFade`.

---

## Sculpted Pill System (UI Visual System V2 → V4, 2026-10-23/24)

**Files**: `frontend/lib/presentation/widgets/paax_pill.dart` (tokens, `PaaxLayout` geometry, primitives, fades), `paax_top_bar.dart` (detail-screen top bar), `PaaxBottomNavigation` in `screens/main_wrapper.dart`, `MiniPlayerArcProgressPainter` in `widgets/mini_player.dart`.

One centralized surface recipe backs the bottom navigation, the Mini Player, top-bar icon pills, segmented filter pills, search fields and the secondary circular action buttons. The Full Player does **not** import it (protected component).

| Token (`PaaxPillTheme`) | Value |
|------|-------|
| Fill | uniform opaque `#111111` (`fill`) — V3 removed the V2 `#101010→#141414` gradient |
| Bevel | `#666666`, 1 logical px, painted as a gradient stroke: top edge @0.50 → sides @0.16 → bottom @0 (`bevelGradient`) |
| Search-field bevel | `#666666@0.28` top → `#191919` (`searchBevelGradient`) |
| Shadow | `black@0.40` blur 10 offset (0,3) + `black@0.20` blur 2 offset (0,1) |
| Active | fill `#FFFFFF`, foreground `#080808` |
| Inactive foreground | `#A0A0A0`; placeholder `#8A8A8A` |
| Fades | `#080808` multi-stop ramps only (`PaaxFade.ramp` = 0 → 8 → 22 → 45 → 72 → 95 %) — **no `BackdropFilter`** anywhere in the system |

| Geometry (`PaaxLayout`) | Value | Used by |
|------|-------|---------|
| `contentHorizontalInset(context)` (alias `floatingInset`) | `Responsive.horizontalPadding` = 6 % of width, clamped 16–24dp (the list-artwork left edge). V4 §4: the single horizontal alignment system — also used by `SectionHeader`, Home/Artist carousels (first item on the inset), Artist/Discography/Library headings, grids and playlist rows, the Album/Playlist header block and the "See full discography" button | Top-bar pills, Mini Player, nav capsule, Search/Library/Discography header rows |
| `topBarHeight` / `topBarPill` | 58dp bar region / 44dp discs, title capsule and search fields | `PaaxTopBar`, Search, Discography, Notifications, Library sort/search |
| `navHeight` / `navIndicatorHeight` × `navIndicatorWidth` | 54dp capsule / 46 × 62dp white indicator (4dp inset, clamped to slot − 8) — V4 §3: 85 % of the V3 64 / 56 × 72 | `PaaxBottomNavigation` |
| `miniPlayerHeight` / `dockGap` | 56dp / 6dp (`kMiniPlayerZone` = 62) — V4 §3: 85 % of the V3 66dp; artwork 42dp, concentric (7dp ring) | Mini Player, dock, Library FAB offset |
| `dockBottomClearance` | 14dp added once to the bottom safe inset (V4 §2): `dockBottom = viewPadding.bottom + 14` lifts the nav capsule *and* the Mini Player together | dock, Library FAB offset |
| `topFadeTail` / `bottomFadeExtra` | 80dp / 96dp | header fades / bottom dock fade (V4 §1: the dock fade is the **only** bottom fade — per-screen bottom gradients were removed from Home, Search, Library, Profile, Artist, Album, Playlist, Discography and Genre so nothing stacks; plateau ends at the nav capsule centre, mirroring the top bar) |

| Widget | Role | Geometry contract |
|--------|------|-------------------|
| `PaaxPillSurface` | The decorated capsule (stadium unless `radius`), `active` → flat white | sizes to child or `width`/`height` |
| `PaaxIconPill` | Circular icon pill | visual disc `size` (44 default) inside a ≥`minTapSize` (48) tap target |
| `PaaxSegmentPill` / `PaaxSegmentedPills` | Filter / tab pills, horizontally scrolling | row height = pill height + `shadowRoom` (8dp); content-sized pills |
| `PaaxSearchPill` | Shell around an unchanged `TextField` | caller keeps controller/focus/debounce; 44dp default |
| `PaaxFade.gradient` / `PaaxHeaderFade` | Atmospheric fade: `plateau` px held at 95 % behind the controls, then a `tail` ramping 72→45→22→8→0 % | `opacity` scales the stops (scroll-tied, no `Opacity` layer); `IgnorePointer` |
| `PaaxTopBar` | Back pill + title capsule + trailing pill over the header fade | 44dp discs whose outer edges sit on `floatingInset` (`controlOffset(inset)` = inset − 2 for the 48dp tap box); title capsule 44dp, padded `inset + 44 + 12`; fade plateau = bar centre, tail 80dp; fade/title animate together (150 ms) |
| `PaaxBottomNavigation` | Floating nav capsule, 54dp, side margins = `floatingInset` | white 46×62 capsule (`indicatorWidth(slot)`) slides between equal slots (`AnimatedAlign`, 220 ms); glyphs 28dp |
| `MiniPlayerArcProgressPainter` | Progress along the Mini Player's **upper** perimeter (left mid → left corner → top edge → right corner → right mid), measured by path length | `repaint: positionNotifier` → repaints only; 2dp stroke inset inside the capsule; track `white@0.10`, done `white@0.90` |
| `PaaxEdgeFade` | Plain top/bottom `#080808` ramp | — |

Migrated call sites: `main_wrapper.dart` (dock fade + nav), `mini_player.dart` (56dp capsule, circular 42dp artwork, arc progress), `search_screen.dart` (back/X pill, 44dp search pill, filter pills, header fade, dedicated search mode — see `SearchScreenMode`), `library_screen.dart` + `library_headers.dart` (header fade, inset-aligned title/tabs/sort/search), `artist_discography_screen.dart` (header fade, back pill, filter pills), `artist_detail_screen.dart` / `album_detail_screen.dart` / `playlist_detail_screen.dart` / `genre_results_screen.dart` (`PaaxTopBar`), `_buildActionButton` in the three detail screens and `track_detail_screen.dart` (secondary buttons only — the primary Play stays a flat white disc with identical size), `notifications_screen.dart` (back pill). `GlassCircleButton` and `GlassPill` in `glass_surface.dart` delegate to the pill primitives.

Pinned headers (Search, Library, Discography) no longer paint an opaque `#080808` rectangle behind their controls: one `PaaxHeaderFade` sits behind the whole control stack, its plateau ends at the vertical centre of the lowest control (pill row / search row) and its 80dp tail dissolves into the list; opacity follows scroll offset (`offset / 40`). Scroll spacers: Search `SearchScreenMode.headerHeight` (`top + 8 + 44 [+ 10 + 42] + 4`), Discography `kDiscographyHeaderBelowStatus` (`58 + 42 + 4`), Library measured (`LibraryLayout.fadePlateauLift` = 28 for the plateau).

**Search dedicated mode (V3 §8.2)**: `SearchScreenMode.isSearchMode(hasFocus, hasText)`; focusing the field hides Browse All / genre grid / category pills (pills return as soon as there is a query because the results flow switches on them), the back pill becomes an X (`Key('search_close')`, semantics "Close search") which unfocuses, clears the query, resets the filter to All and restores the browse screen without leaving the tab. Empty-query search mode renders nothing — reserved for local search history (not implemented, no storage).

---

## Don'ts

- Do not pass `enableBlur: true` expecting real blur — it is ignored everywhere except the full player's own `BackdropFilter`.
- Do not use `network_image_with_fallback` / `smart_network_image` / `queued_network_image` in new code — use `AppImage`/`Thumbnail` (they carry the 429-throttling pipeline). See [frontend/widgets.md](../frontend/widgets.md).
- Do not hardcode `white.withOpacity(0.08)` borders — reference `BeatyGlassTokens.borderOpacity`.
- Do not rely on `GlassCircleButton`'s default 40px size for a primary tap target on its own — pad the hit area toward 48px.

---

*Last updated: 2026-07-16*
