# PR texts (copy as-is). Order: PR 1 → PR 2 → PR 3. Nothing is pushed until each stage is authorized.

---

## PR 1 — `feat/ui-sculpted-pills` → `main` (uzielcezate/paax-frontend)

**Title:** UI: Visual System V2/V3/V4 — monochrome sculpted pills, floating back buttons, player density

**Body:**

Mobile-first visual pass on the existing screens. No navigation, playback, data or state-management changes.

- New shared surface recipe `PaaxPill` (bottom navigation, Mini Player, top-bar icon pills, segmented filters, search fields, circular secondary actions), V3 precision pass, V4 geometry/spacing/fade refinements.
- New `PaaxTopBar` (pill top bars with floating circular Back buttons) and `PlayerVerticalFrame`.
- Mini Player and full player density/metrics; `MarqueeText` rewrite; restyled Home, Search, Library, Album/Artist/Discography/Genre/Playlist/Track detail, Notifications, Profile, MainWrapper, Player.
- Tests: paax_pill, player_vertical_frame, mini_player_progress, search_screen_mode, player_layout_metrics, marquee_text. Docs: design system, colors, components, player, widgets.

Validation: `flutter analyze` 0 errors; `flutter test` 770 passed, 1 failed (`widget_test.dart` "App smoke test", pre-existing path_provider failure in the VM runner, identical on `main`). Physical-device QA: ✅ (fill in date).

Single commit `0cab89c`, 36 files.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## PR 2 — `worktree-web-demo-mode` → `main` (stacked on PR 1; fast-forwards after PR 1 merges)

**Title:** Feat: secure portfolio demo mode on Flutter Web (`?demo=1`) + web-only fixes

**Body:**

Additive, off by default: `DemoMode.isRequested` is false on every normal launch and on mobile, so `AuthGate` and all existing flows are unchanged. The playback architecture (YouTube IFrame engines, matching, lifecycle, mini/full player) is frozen; the only playback-related files touched are listed under "web fixes".

Commits (reviewable one by one):
1. `b3b8404` Fix(web): restore the web build (`media_session_web.dart` was fully commented out → no-ops with the stub's signatures); platform-view iframe swallowed taps in the top-left 300×300 (`IgnorePointer` + `pointer-events:none`, `playback_engine_web.dart`); `ThrottledCacheManager` needed `path_provider` on web (memory-only repo on web).
2. `bd680d2` Feat(demo): `DemoGate` around the real app, `DemoSessionController` (server-authoritative 10-min countdown, 60 s re-validation, expiry/restart), API + Supabase session adapter, `_headers` (CSP frame-ancestors = portfolio) and `_redirects`, `PlaybackController.resetForDemoEnd()` (demo wiring only), 12 unit tests.
3. `b388b11` Feat(supabase): `demo_sessions` migration (PostgREST pre-request guard, pg_cron cleanup) — **not applied here; separate release stage**.
4. `311bb04`, `6e42d77` Docs.
5. `83c9020` Fix(image): `AppImage` re-requests load when its URL changes while already visible (album header placeholder root cause).

Validation (local Supabase + local paax-api + release web bundle, pointer-only Chrome): real IFrame playback, mini-player pause/resume, Search → Artist, Library/Profile, forced and natural expiry stop playback and end the session, Restart mints a new identity, reload after expiry cannot resurrect a session, two simultaneous visitors isolated by RLS. `flutter analyze` 0 errors; `flutter test` 782 passed, 1 pre-existing failure.

Not in this PR: Railway variables, Supabase migration apply, Cloudflare Pages, DNS (see `docs/runbooks/demo-release/`).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## PR 3 — paax-api `feat/demo-sessions` → `main`

**Title:** Feat: demo sessions (`/v2/demo/*`), disabled by default; CORS allowlist support; publishable key

**Body:**

Additive; no existing route, model or auth path changes. Deploy with `DEMO_ENABLED` unset (feature answers 503) — activation is a separate stage after the Supabase migration and origin checks.

Commits:
1. `b76d906` Demo sessions: per-visitor throwaway Supabase identities (service role) with server-authoritative expiry; GoTrue token exchange with the PUBLIC key (`SUPABASE_PUBLISHABLE_KEY` preferred, `SUPABASE_ANON_KEY` fallback; `sb_secret_` refused); status/end/sweep; per-IP + global rate limits; kill switch. `FRONTEND_ORIGINS` comma parser, anchored local-dev regex, optional `FRONTEND_ORIGIN_REGEX`.
2. `d88be19` CORS allowlist tests + `.env.example`.
3. `49aa06a` `DEMO_ENABLED` defaults to **false**.
4. `fe29d50` Rate limiter keys on `CF-Connecting-IP`, then the rightmost `X-Forwarded-For` hop (production is client → Cloudflare → Railway edge → app; first-hop trust was spoofable).

Tests: 120 passed. Railway variable plan and activation order: `docs/features/demo-mode.md` → "Production release checklist" in paax-frontend.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
