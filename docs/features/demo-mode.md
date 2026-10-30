# Feature: Portfolio Demo Mode (web)

> **Purpose**: How a visitor of `https://uzielsandoval.com` explores the real PAAX app for ten minutes without registering, and how that is kept secure and isolated.
> **Status (2026-10-30)**: implemented locally on the `worktree-web-demo-mode` worktree (frontend) and `feat/demo-sessions` (paax-api). **Not deployed, migration not applied, no PR.**
> **Update when**: the demo endpoints, the session lifecycle, the database guard, or the portfolio contract change.

---

## Overview

Demo mode is an **additive, opt-in** entry point of the existing Flutter **web** build. Nothing in normal PAAX changes: mobile keeps `AuthGate`, login, registration, onboarding and every screen exactly as before. Demo mode is only entered when the web app is launched with a demo marker in the URL **and** the backend has minted a valid demo session.

```
Start Demo (portfolio) → iframe https://paaxmusic.app/?demo=1
  → DemoGate → POST api.paaxmusic.app/v2/demo/sessions
  → paax-api mints a throwaway Supabase identity (service role), returns its session tokens
  → Flutter adopts the session (supabase.auth.setSession) → AuthController sees `signedIn`
  → real startup machine → real Home / Search / Artist / Album / Player
  → 600 s later (server authority) → playback paused, identity deleted, "Demo Session Ended"
  → Restart Demo → a NEW identity, a fresh 600 s
```

**Each visitor is an independent identity.** Isolation is the existing Row Level Security (every private table is keyed by `auth.uid()`); two visitors can no more see each other's library than two real users can. No shared account, no shared tokens, no credentials in the client. The dedicated test account `paaxmusic.app@gmail.com` is **not used** by the demo.

---

## Components

| Layer | File | Role |
|-------|------|------|
| paax-api | `services/demo/demo_session_service.py` | `DemoSessionService`: create / status / end / sweep. Injected gateway, auth-admin and token client (unit-testable without network). |
| paax-api | `api/demo_router.py` | `/v2/demo/*` endpoints, per-IP + global rate limits, kill switch. |
| paax-api | `config.py`, `app_container.py`, `main.py` | Additive settings (`DEMO_*`, `SUPABASE_PUBLISHABLE_KEY` preferred / `SUPABASE_ANON_KEY` legacy fallback), service construction, router mount. |
| paax-api | `repositories/supabase_client.py` | Additive `insert` / `delete` / `auth_admin` on the existing gateway. |
| Database | `supabase/migrations/20261030000000_demo_sessions.sql` | `demo_sessions` table (authoritative expiry), `demo_session_status()` RPC, PostgREST pre-request guard, `private.demo_cleanup()` + pg_cron. **Not applied yet — see [Database guard review](#database-guard-review).** |
| Flutter | `core/demo/demo_mode.dart` | `DemoMode.isRequested` — `kIsWeb` && (`?demo=1` \| `/demo` \| `#/demo`). |
| Flutter | `data/remote/demo_session_api.dart` | HTTP client for the three endpoints. |
| Flutter | `data/remote/supabase_demo_session_adapter.dart` | The only Supabase touchpoint: `setSession(refreshToken, accessToken: …)`, `signOut(scope: local)`, `app_metadata.paax_demo` check. **Both tokens are required**: with a refresh token alone the SDK emits `tokenRefreshed`, which `AuthController` intentionally ignores (no profile re-resolution on refresh), and the shell stays on Welcome — found in staging. With the access token it emits `signedIn`, exactly like a password login. |
| Flutter | `presentation/state/demo_session_controller.dart` | `DemoSessionController`: idle → starting → active → ending → ended / error; server-seeded countdown; 60 s server re-validation; pause playback + clear local state on end; `postMessage` lifecycle events. |
| Flutter | `presentation/screens/demo/demo_gate.dart`, `demo_screens.dart` | `DemoGate` wraps the existing `AuthGate`; Starting / Ended ("Restart Demo") / Error screens. |
| Flutter | `main.dart` | Two additive lines: a lazy `DemoSessionController` provider and `home: DemoMode.isRequested ? DemoGate : AuthGate`. |
| Flutter | `core/playback/media_session_web.dart` | **Web compile fix** (unrelated to demo but required for any web build): the file was entirely commented out, so `flutter build web` failed with three undefined-method errors. Now defines the four media-session functions as documented no-ops with the mobile signatures. Mobile uses `media_session_stub.dart` and is untouched. |

---

## Session lifecycle (server authority)

| Moment | Server | Client |
|--------|--------|--------|
| Start | `admin.create_user` (random email `demo-<uuid>@demo.paaxmusic.app`, random 32-byte password never stored, `email_confirm=true`, `app_metadata.paax_demo=true`), profile completed (`display_name`, `birth_date`, `country_code`, `onboarding_completed`), `demo_sessions` row with `expires_at = now()+600s`, password grant with the public API key (`sb_publishable_…` preferred, legacy anon JWT fallback; sent only as the `apikey` header, never decoded) | `setSession(refresh_token)`; countdown seeded from `duration_seconds` (not from the browser clock vs. an absolute time) |
| Active | `GET /v2/demo/sessions/me` returns `remaining_seconds`; PostgREST guard rejects the identity once `expires_at <= now()` | ticks every second; every 60 s re-seeds from the server; `postMessage` `tick` |
| Reload / modal reopened | same row, same expiry | `bootstrap()` finds the persisted Supabase session → asks the server → resumes with the server's remaining time, or shows **Ended** if it expired meanwhile. Never a fresh ten minutes. |
| End (timer, sign-out, explicit) | `POST /v2/demo/sessions/end` marks `ended_at` and **deletes the auth user** (cascade wipes profile, likes, playlists, notifications) | pauses playback (`togglePlayPause` only if playing), local sign-out, `HiveStorage.clearAll()`, Ended screen, `postMessage` `ended` |
| Abandoned | `private.demo_cleanup()` via pg_cron every minute (+ a best-effort sweep on every create) deletes identities whose `expires_at` passed 60 s ago | — |
| Restart | a brand-new identity | `restart()` → `start()` |

### What the JWT can and cannot do after expiry

Deleting the user invalidates the refresh token immediately. A previously issued **access token stays cryptographically valid until its own `exp`** (project default 1 h). The PostgREST pre-request guard closes that window for the whole Data API (`/rest/v1/*`, including RPC). Surfaces **not** covered by the guard:

- **Realtime**: channel authorization re-reads RLS on subscribe; an already-open channel for a deleted user receives nothing because its rows are gone. Demo users only subscribe to their own playlists/notifications.
- **Storage**: `user-avatars` policies are keyed by `auth.uid()`; a deleted demo user could still upload an avatar object into its own folder until the JWT expires. Low impact; the folder is orphaned. If this matters, add `private.demo_session_active(auth.uid())` to the avatar insert policy.
- **paax-api catalog endpoints**: public by design (no auth), unaffected.

---

## Database guard review

The migration installs `public.paax_pre_request()` as `pgrst.db_pre_request` on the `authenticator` role.

**Cost for normal users**: one `current_setting('request.jwt.claims')` read and two JSONB key lookups, then `return`. No table access. Measured in microseconds; no new round-trip (it runs inside the same transaction PostgREST already opens).

**Cost for demo users**: one primary-key lookup on `demo_sessions` per request.

**Failure containment**: every branch that is not the deliberate demo rejection is wrapped so an unexpected error returns instead of raising; the function is `security definer` with an empty `search_path` and reads only `demo_sessions`.

**Rollback** (two statements, instant):
```sql
alter role authenticator reset pgrst.db_pre_request;
notify pgrst, 'reload config';
```

**Alternatives considered**

| Option | Coverage | Global impact | Verdict |
|--------|----------|---------------|---------|
| Pre-request hook (chosen) | All Data API requests of demo identities, incl. RPCs | One claims check per request for everyone | Recommended |
| RLS predicate `private.demo_session_active()` on every table | All tables, but 34 policies to edit and keep in sync | Per-row function call | Rejected: invasive, easy to miss a table |
| Deletion only (pg_cron + sweep) | Refresh blocked instantly; access JWT lives up to 1 h | None | Fallback if the hook is declined |
| Shorter project-wide JWT lifetime | Shrinks the window for everyone | Changes real users' token cadence | Rejected |

**Social actions blocked for demo identities** (HTTP 403 `DEMO_ACTION_NOT_ALLOWED`): `playlist_invite_collaborator*`, `search_invitable_profiles`, `playlist_transfer_ownership`, writes to `user_friendships` / `user_blocks`. Everything else a real user can do (like, save, create playlists, follow) works and is deleted with the identity.

---

## Portfolio integration contract

### Embedding (recommended — the Flutter app does everything)

```html
<!-- Start Demo button → mount this iframe -->
<iframe
  src="https://paaxmusic.app/?demo=1"
  allow="autoplay; encrypted-media; fullscreen"
  referrerpolicy="strict-origin-when-cross-origin"
  style="width:393px;height:852px;border:0;border-radius:48px"></iframe>
```

- The app mints its own session on load (no call from the portfolio needed), shows the real Home, and at zero shows **Demo Session Ended → Restart Demo** by itself.
- Reopening the modal within the ten minutes resumes the same session; the timer is not reset.
- **Lifecycle events** are posted to the parent window as JSON strings; the portfolio can render its own timer from them:

```js
window.addEventListener('message', (e) => {
  if (e.origin !== 'https://paaxmusic.app') return;
  const m = JSON.parse(e.data);                 // { type: 'paax-demo', event, ... }
  if (m.type !== 'paax-demo') return;
  // event: 'started' {remainingSeconds, expiresAt} | 'tick' {remainingSeconds}
  //        | 'ended' {reason: 'expired'|'signed_out'|'ended'} | 'error' {message}
});
```

- **Requirements on the paaxmusic.app host**: send `Content-Security-Policy: frame-ancestors 'self' https://uzielsandoval.com https://www.uzielsandoval.com` (and no `X-Frame-Options: DENY`). Serve `index.html` for `/demo` if the path form is used; the query form `?demo=1` needs nothing.
- **Autoplay**: the first play always follows a tap inside the iframe (browser policy); `allow="autoplay"` lets subsequent tracks continue.
- Development origins (`http://localhost:*`, `127.0.0.1`) are already allowed by paax-api's CORS regex.

### Direct API (optional — only if the portfolio wants to pre-create the session)

| | |
|---|---|
| Endpoint | `POST https://api.paaxmusic.app/v2/demo/sessions` |
| Body | `{ "client": "portfolio" }` (optional, ≤40 chars) |
| Auth | none (rate-limited: 6 per IP per 10 min, 120 per hour globally) |
| Response `201` | see below |
| Errors | `429 DEMO_RATE_LIMITED` (+`Retry-After`), `503 DEMO_DISABLED`, `502 DEMO_IDENTITY_CREATE_FAILED`, `502 DEMO_TOKEN_EXCHANGE_FAILED` |

```json
{
  "session": { "id": "<uuid>", "started_at": "…Z", "expires_at": "…Z",
               "duration_seconds": 600, "server_time": "…Z" },
  "auth":    { "access_token": "…", "refresh_token": "…", "token_type": "bearer", "expires_in": 3600 },
  "user":    { "id": "<uuid>", "username": "demo_1a2b3c4d", "display_name": "Demo Visitor" },
  "launch":  { "web_url": "https://paaxmusic.app/?demo=1", "client": "portfolio" }
}
```

`GET /v2/demo/sessions/me` and `POST /v2/demo/sessions/end` take `Authorization: Bearer <access_token>` and answer `{"session": {"id", "active", "remaining_seconds", "expires_at", "server_time"}}` / `{"session": {"id", "active": false, "ended": true}}`. `401 DEMO_UNAUTHORIZED`, `403 DEMO_NOT_A_DEMO_USER`.

The tokens are those of a throwaway identity that the server deletes at expiry; they are not reusable across sessions. Treat them like any user session (do not log them). For the direct flow the portfolio origin **must** be in `FRONTEND_ORIGINS`; the iframe flow needs only `https://paaxmusic.app` there (already the case).

### Required configuration (production)

| Where | Variable | Value |
|-------|----------|-------|
| Railway `paax-api` | `SUPABASE_PUBLISHABLE_KEY` | the project's modern public key (`sb_publishable_…`, Dashboard → API Keys). Preferred. Opaque string, not a JWT. |
| Railway `paax-api` | `SUPABASE_ANON_KEY` | legacy anon JWT — only consulted when `SUPABASE_PUBLISHABLE_KEY` is empty (backward compatibility). Never set an `sb_secret_` key here (rejected at startup). |
| Railway `paax-api` | `FRONTEND_ORIGINS` | replace the current wildcard `*` with the explicit allowlist `https://paaxmusic.app,https://www.paaxmusic.app,https://demo.paaxmusic.app,https://uzielsandoval.com,https://www.uzielsandoval.com` (see *CORS allowlist audit* below) |
| Railway `paax-api` | `FRONTEND_ORIGIN_REGEX` | optional, only while testing Cloudflare Pages previews: `https://[a-z0-9-]+\.<pages-project>\.pages\.dev`; remove afterwards |
| Railway `paax-api` | `DEMO_ENABLED` | `true` (default) — set `false` to kill the feature instantly |
| Railway `paax-api` | `DEMO_SESSION_SECONDS`, `DEMO_RATE_LIMIT_PER_IP`, `DEMO_RATE_LIMIT_WINDOW_SECONDS`, `DEMO_RATE_LIMIT_GLOBAL`, `DEMO_EMAIL_DOMAIN`, `DEMO_DISPLAY_NAME`, `DEMO_WEB_URL` | optional overrides (defaults 600 / 6 / 600 / 120 / `demo.paaxmusic.app` / `Demo Visitor` / `https://paaxmusic.app/?demo=1`) |
| Supabase | migration `20261030000000_demo_sessions.sql` | apply after review |
| Web host | CSP `frame-ancestors` | see above |

---

## Staging validation (local Supabase CLI stack, 2026-10-30)

Run on `npx supabase start` (Postgres 17.11, PostgREST v16.5, GoTrue v2.197, pg_cron 1.6.4) with every repository migration applied in order, including `20261030000000_demo_sessions.sql`, plus a local paax-api (`SUPABASE_URL/SERVICE_ROLE` + a public key = local dev keys, no Redis).

#### CORS allowlist audit (2026-10-30)

Production `FRONTEND_ORIGINS` is currently `*`. Who actually sends an `Origin` header to paax-api:

| Client | Origin sent | Covered by |
|---|---|---|
| PAAX mobile (Android/iOS, Dart `http`/Dio) | none — CORS does not apply to native HTTP | n/a (unaffected by any allowlist) |
| Flutter Web at `https://paaxmusic.app` / `https://www.paaxmusic.app` | that origin | `FRONTEND_ORIGINS` |
| Flutter Web demo at `https://demo.paaxmusic.app` (iframe content; the iframe's own origin is what counts, not the embedding page) | `https://demo.paaxmusic.app` | `FRONTEND_ORIGINS` |
| Portfolio `https://uzielsandoval.com` / `www` — only if it calls `/v2/demo/sessions` directly instead of embedding | that origin | `FRONTEND_ORIGINS` |
| Local dev: `flutter run -d chrome` (`http://localhost:<random>`), local release build (`http://127.0.0.1:8087`), Android emulator `10.0.2.2`, LAN devices `192.168.x.x` / `10.x` / `172.16-31.x` | localhost/private-IP origins | built-in regex, always on (anchored, scheme http/https, any port) |
| Cloudflare Pages previews `https://<hash>.<project>.pages.dev`, `https://<branch>.<project>.pages.dev` | random per deploy, cannot be enumerated | new optional `FRONTEND_ORIGIN_REGEX` (additive; unset = previews not allowed) |
| Supabase, Deezer, YouTube calls | go to those services, not to paax-api | n/a |

Parser: `FRONTEND_ORIGINS` is split on commas, each entry trimmed, empties dropped (spaces around commas are fine). Scheme is part of the origin (`http://paaxmusic.app` is **not** allowed by an `https://` entry). Tested in `tests/test_cors_origins.py` with the exact middleware arguments main.py derives: preflight (`OPTIONS` with `Access-Control-Request-Headers: authorization,content-type`) → 200 with `Access-Control-Allow-Origin` echoing the origin and `Allow-Credentials: true`; authenticated `GET` with `Authorization: Bearer` → 200 + ACAO; unlisted origin → preflight 400 and no ACAO on simple requests (the request itself is still served, which is how mobile and server-to-server traffic keep working); requests with no `Origin` header → unaffected; local-dev regex is anchored (`http://localhost.evil.example` rejected).

**Final tested value:** `FRONTEND_ORIGINS=https://paaxmusic.app,https://www.paaxmusic.app,https://demo.paaxmusic.app,https://uzielsandoval.com,https://www.uzielsandoval.com`

#### Public API key: publishable vs legacy anon (2026-10-30)

The demo token exchange accepts either public key kind; selection is `SUPABASE_PUBLISHABLE_KEY` → `SUPABASE_ANON_KEY` → disabled (`Settings.supabase_public_api_key`). The key is an opaque `apikey` header value: it is never decoded, never verified, never used as a Bearer token, and `sb_secret_…` is refused by `GoTrueHttp`. Verified against the local stack (GoTrue v2.197 / PostgREST v16.5) with the exact production class, side by side with the legacy anon JWT:

| Check | publishable | legacy anon |
|---|---|---|
| `GET /auth/v1/settings` | 200 | 200 |
| password grant → JWT access + refresh token (`expires_in` 3600) | 200 | 200 |
| `GET /auth/v1/user` with the issued token (`app_metadata.paax_demo=true`) | ok | ok |
| `refresh_token` grant | 200 | 200 |
| PostgREST with `apikey`=key + user Bearer: active session → own profile 200; demo user **without** a `demo_sessions` row → `401 PT401 DEMO_SESSION_EXPIRED` (guard, not gateway) | ✅ | ✅ |
| key itself used as Bearer → treated as the anonymous role (no privilege) | 200/anon | 200/anon |
| Full `/v2/demo/sessions` → `/me` → `/end` with **only** `SUPABASE_PUBLISHABLE_KEY` set (`SUPABASE_ANON_KEY` empty) | 201 / 200 / 200, then `/me` 401 | n/a |

Production (read-only, no writes): the project's `sb_publishable_…` key returns 200 on `/auth/v1/settings` and `/rest/v1/genres`; a bogus key returns 401, so the gateway enforces it. Supabase SDK compatibility: `supabase` 2.14 / `supabase_flutter` 2.16 document passing the publishable key as the client key and only ever send it as the `apikey` header, so the Flutter web build may be given the publishable key through the existing `SUPABASE_ANON_KEY` dart-define without code changes (the mobile default stays the legacy anon key; not changed). Existing auth flows are untouched: the service-role gateway, `admin.create_user`, RLS and the pre-request guard do not depend on which public key kind is configured.


| Check | Result |
|---|---|
| Migration applies cleanly after the 30 existing ones | ✅ `pgrst.db_pre_request=public.paax_pre_request` set on `authenticator`; `cron.job` `paax_demo_cleanup` `* * * * *` scheduled |
| Normal registration + login (GoTrue) | ✅ signup → profile row created by the existing trigger; password login returns a session |
| Normal user reads own profile / writes own rows through PostgREST | ✅ 200 / RLS write path reached (409 only because the fixture track id does not exist) — the guard is a no-op for non-demo JWTs |
| `demo_session_status()` for a real user | ✅ `{active:false, remaining_seconds:0}` |
| `POST /v2/demo/sessions` | ✅ identity + completed profile (`onboarding_completed=true`) + `demo_sessions` row, `expires_at = start + 600 s`, tokens returned |
| Demo user reads only its own profile; real user sees no `demo_sessions` rows | ✅ isolation by RLS |
| Demo user calls `search_invitable_profiles` | ✅ **403** `DEMO_ACTION_NOT_ALLOWED` |
| Force `expires_at < now()` then reuse the SAME still-valid JWT | ✅ **401** `{"code":"PT401","hint":"DEMO_SESSION_EXPIRED"}` on tables and RPCs; `GET /v2/demo/sessions/me` → `active:false` |
| Service-role and anon requests during all of the above | ✅ 200 (unaffected) |
| `private.demo_cleanup()` | ✅ respects the 60 s grace (0 deleted at +2 s), then deletes the identity: `auth.users`, `profiles`, `demo_sessions` all 0 for that id; the real staging user remains |

Not covered by the guard (documented gaps, unchanged): Realtime channels and Storage objects of an already-issued demo JWT until that JWT's own `exp` (≤ 1 h) — rows are already deleted, so Realtime delivers nothing; Storage could accept an avatar upload into the deleted user's folder.

## Flutter Web validation (browser E2E, 2026-10-30)

All runs: local release bundle (`flutter build web --release -o build/web-local`, local dart-defines) served by a static SPA server on `127.0.0.1:8087`, local paax-api on `:8000` (publishable key only, planned `FRONTEND_ORIGINS`), local Supabase CLI stack. Driven by a puppeteer-core harness with **pointer events only** (no accessibility overlay), one Chrome at a time, fresh profile per run. Everything in this section is **staging** evidence; nothing was run against production services.

### Root causes fixed (web only, additive)

| Symptom on web | Root cause | Fix |
|---|---|---|
| Taps on the first Trending card, the Search field, "Top Result" and the artist header did nothing; album rows sometimes "did nothing" | The hidden YouTube player is a real DOM `<iframe id="youtube-0">` (platform view) sitting 300×300 at the page's top-left. The browser delivers pointer events to the iframe **before** Flutter hit-testing, so every tap in that square was swallowed (`elementsFromPoint` → `IFRAME#youtube-0`, `pointer-events: auto`). | `playback_engine_web.dart` (web-only file): wrap the player in `IgnorePointer` and, once the platform view mounts, set `pointer-events: none` on the iframe and its `flt-platform-view` host. Probe after fix: `FLT-GLASS-PANE` is the top element, iframe `pointer-events: none`. |
| `MethodChannel` error on Artist detail (`MissingPluginException … getApplicationSupportDirectory … path_provider`) | `ThrottledCacheManager` hard-codes `JsonCacheInfoRepository`, which needs `path_provider` (no web implementation). | `throttled_cache_manager.dart`: on web use flutter_cache_manager's memory-only `NonStoringObjectProvider`; mobile unchanged. Artist page now loads with zero Dart errors. |
| After "Restart Demo" the new run inherited the previous run's mini-player track (pause icon shown, YouTube frame merely cued) | The app-scoped `PlaybackController` keeps its in-memory queue across the demo end; `pausePlayback` only toggled play/pause. | New additive `PlaybackController.resetForDemoEnd()` (pause engine + clear queue/confirmed snapshot), called only from the demo wiring in `main.dart`. Normal mobile/web flows never call it. |

### Verified flows

| Flow | Result |
|---|---|
| Home → first Trending card → Album detail | ✅ opens; cold albums can take 15–20 s to ingest before rows appear (upstream, pre-existing) |
| Album row tap → authorized YouTube IFrame playback | ✅ `youtubei/v1/player` + `googlevideo` media segments; inner `YT.Player` state 1 with clock advancing (e.g. 2.0 → 7.2 s, video `sbqVXN4qulQ`) |
| Mini player pause / resume | ✅ pause → state 2, clock frozen (7.3 → 7.3 s); resume → state 1, clock advancing (10.3 s) |
| Full player opens from the mini player | ✅ |
| Search field focus + typing → Top Result → Artist detail | ✅ `focused: INPUT`; artist page renders header, Latest Release, Albums; **no Dart errors** |
| Library tab, Profile tab (Demo Visitor identity) | ✅ |
| Forced server expiry (`expires_at` moved into the past in the db) while a track plays | ✅ "Demo Session Ended" within the 60 s re-validation window (36 s); player frame torn down, no further media requests; local SDK session cleared; the still-valid JWT gets `401 PT401 DEMO_SESSION_EXPIRED` from PostgREST; identity swept by `paax_demo_cleanup` within a minute |
| Natural expiry (API started with `DEMO_SESSION_SECONDS=90`) while a track plays | ✅ ended at the server deadline; client `/end` deleted the identity immediately (`auth.users` 0); playback stopped (state 5, no media growth) |
| "Restart Demo" | ✅ new identity (`uid` differs), fresh `demo_sessions` row, Home with an **empty** player |
| Hard reload after an expiry (stale-token resurrection) | ✅ no persisted token; a fresh identity is minted and Home loads; old identity gone |
| Two visitors at once (two Chrome profiles, both sessions live simultaneously) | ✅ different `uid`/username; each sees only its own profile, its own `demo_sessions` row, its own private playlist (`isolation-p1` / `isolation-p2`) |

### YouTube error 150 from a loopback origin (staging artifact, not an app bug)

From `http://127.0.0.1:8087` most label-owned videos (Sony/UMG catalog, e.g. `FWUxBeV0ikw`, `iPGporuhqT8`) fail with `onError 150` ("owner does not allow embedded playback"), while independent uploads (`vbC4FkqMvTY`) play. The mobile engine already documents the mechanism: it loads the player with `baseUrl: https://paaxmusic.app` "so YouTube can verify the Referer and allow playback of restricted music videos". A standalone IFrame-API page (no Flutter) reproduces it from loopback, and with the browser's `Referer` rewritten to `https://demo.paaxmusic.app/` **all three** ids play. Consequently the full-app runs above used the harness's `REF=https://demo.paaxmusic.app/` rewrite. On the real `demo.paaxmusic.app` origin the Referer is genuine, so no code change is needed; this is also why the demo must be served from a real domain, never from `*.pages.dev` only. **Not yet proven on the real domain** (needs the Cloudflare Pages deployment). When a video does refuse embedding, the existing (platform-independent) behaviour applies: the play transaction fails and the app shows "Unable to play this track".

### Other observations

- `405 HEAD http://127.0.0.1:8000/` in the console: the legacy `youtube_music_data_source` warm-up pings the API root with `HEAD`; FastAPI answers 405. Harmless, pre-existing, same on production.
- With the accessibility semantics overlay enabled, the merged album-row node's tap action resolves to the row's overflow menu instead of play (pointer taps are fine). Minor a11y issue, not visitor-facing.
- Generated desktop registrant files (`linux/`, `windows/`, `macos/` `generated_plugin*`) were touched by the toolchain only to add `connectivity_plus`; noise, not part of the change.

## Testing

- paax-api: `tests/test_demo_sessions.py` — identity minting (flag, confirmed email, random password never returned), independent identities/expiries for two visitors, rollback on token-exchange failure, server-authoritative status/expiry, end marks + deletes, sweep grace window, router create/status/end, per-IP rate limit via `X-Forwarded-For`, kill switch, existing routes untouched. Plus `tests/test_cors_origins.py` (allowlist parser, preflight/authenticated requests, anchored local regex, optional Pages-preview regex). Full suite: 117 passed.
- Flutter: `test/unit/demo_mode_test.dart` (URL opt-in, never on mobile), `test/unit/demo_session_controller_test.dart` (start, expiry side effects, restart mints a new identity, reload resumes remaining time, reload of an expired session ends, server re-validation wins, sign-out guard, rate-limit error + retry). Full unit+widget suite (worktree, 2026-10-30): 708 passed, 1 failed — `test/widget_test.dart` "App smoke test" fails identically on `main` (pre-existing `path_provider` MissingPluginException in the VM test runner), unrelated to the demo work.
- Browser E2E (puppeteer-core, pointer-only, local stack): see "Flutter Web validation" above — Start → Home → Album → Play → mini player → Search → Artist → Library/Profile → expiry (forced and natural) → Restart → reload; two visitors in two browser profiles see only their own rows.

---

## Known limitations

- Demo identities see the same Home a brand-new real user sees (Trending / Recently added + whatever they follow during the session). No follows are seeded: fake taste would be indistinguishable from real recommendation logic.
- `https://paaxmusic.app` currently answers Cloudflare 522/525 (origin down); the embed cannot work until the web host is restored. See [current-state](../current-state.md).
- The profile email shown in Profile is the generated `demo-…@demo.paaxmusic.app` address.
- Label-owned YouTube videos refuse embedding from loopback/IP origins (error 150); the demo must run from a real domain (`demo.paaxmusic.app`). Real-domain playback is unverified until the Pages deployment exists.
- Cold album pages (first ingestion of an album) can take 15–20 s before track rows appear.
