# Feature: Portfolio Demo Mode (web)

> **Purpose**: How a visitor of `https://uzielsandoval.com` explores the real PAAX app for ten minutes without registering, and how that is kept secure and isolated.
> **Status (2026-11-06)**: released and validated, **demo disabled** pending portfolio launch. Frontend `main` `f1868b1` (PRs #100, #101, #103 — service worker v2; live on Vercel and on Cloudflare Pages project `paax-demo`), paax-api `main` `ae08872` (PRs #6, #7, #8 — password-policy fix; live on Railway with `DEMO_ENABLED=false`, `DEMO_REQUIRE_RATE_LIMITER=true`, `DEMO_RATE_LIMIT_GLOBAL=20`). Supabase migration applied to production (2026-11-04, post-apply checks green). Final host `https://demo.paaxmusic.app` active (Stage 4C). Controlled activations (Stages 5, 5.2) validated identity minting, rate limiting, isolation, lifecycle and cleanup end to end; see [Production status](#production-status-2026-11-06). **Open blocker:** YouTube embedded playback in the web demo fails with error 150 since 2026-11-06 (credentialless player frame; playback engine untouched, fix needs separate approval). Pending: that fix, portfolio iframe integration and public activation (`DEMO_ENABLED=true`).
> **Update when**: the demo endpoints, the session lifecycle, the database guard, or the portfolio contract change.

---

## Overview

Demo mode is an **additive, opt-in** entry point of the existing Flutter **web** build. Nothing in normal PAAX changes: mobile keeps `AuthGate`, login, registration, onboarding and every screen exactly as before. Demo mode is only entered when the web app is launched with a demo marker in the URL **and** the backend has minted a valid demo session.

```
Start Demo (portfolio) → iframe https://demo.paaxmusic.app/?demo=1
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
| Database | `supabase/migrations/20261030000000_demo_sessions.sql` | `demo_sessions` table (authoritative expiry), `demo_session_status()` RPC, PostgREST pre-request guard, `private.demo_cleanup()` + pg_cron. **Applied to production on 2026-11-04** (runbook `docs/runbooks/demo-release/`, post-apply checks green; `paax_demo_cleanup` runs every minute). See [Database guard review](#database-guard-review). |
| Flutter (web) | `web/custom_service_worker.js` | App-shell service worker **v2** (`paax-app-shell-v2`): the navigation shell is cached under `./` only and served only when it is a successful, non-redirected HTML response. v1 pre-cached `./index.html`, which Cloudflare Pages answers with a `308` to `/`, and browsers reject a redirected response for a navigation (`ERR_FAILED` on every visit after the first). Details and tests: `docs/frontend/web-service-worker.md`, `test/web_sw/`. |
| Flutter | `core/demo/demo_mode.dart` | `DemoMode.isRequested` — `kIsWeb` && (`?demo=1` \| `/demo` \| `#/demo`). |
| Flutter | `data/remote/demo_session_api.dart` | HTTP client for the three endpoints. |
| Flutter | `data/remote/supabase_demo_session_adapter.dart` | The only Supabase touchpoint: `setSession(refreshToken, accessToken: …)`, `signOut(scope: local)`, `app_metadata.paax_demo` check. **Both tokens are required**: with a refresh token alone the SDK emits `tokenRefreshed`, which `AuthController` intentionally ignores (no profile re-resolution on refresh), and the shell stays on Welcome — found in staging. With the access token it emits `signedIn`, exactly like a password login. |
| Flutter | `presentation/state/demo_session_controller.dart` | `DemoSessionController`: idle → starting → active → ending → ended / error; server-seeded countdown; 60 s server re-validation; pause playback + clear local state on end; `postMessage` lifecycle events. |
| Flutter | `presentation/screens/demo/demo_gate.dart`, `demo_screens.dart` | `DemoGate` wraps the existing `AuthGate`; Starting / Ended ("Restart Demo") / Error screens. |
| Flutter | `main.dart` | Two additive lines: a lazy `DemoSessionController` provider and `home: DemoMode.isRequested ? DemoGate : AuthGate`. |
| Flutter | `core/playback/media_session_web.dart` | **Web compile fix** (unrelated to demo but required for any web build): the file was entirely commented out, so `flutter build web` failed with three undefined-method errors. Now defines the four media-session functions as documented no-ops with the mobile signatures. Mobile uses `media_session_stub.dart` and is untouched. **Intended final behaviour (owner, 2026-11-03): web keeps YouTube's own browser media metadata; do not re-enable the old JS bridge.** |

---

## Session lifecycle (server authority)

| Moment | Server | Client |
|--------|--------|--------|
| Start | `admin.create_user` (random email `demo-<uuid>@demo.paaxmusic.app`, random 40-character one-time password that satisfies the project's Auth password policy (lower + upper + digit + symbol, CSPRNG), never stored or logged, with exactly one retry on `AuthWeakPasswordError` — paax-api PR #8, `email_confirm=true`, `app_metadata.paax_demo=true`), profile completed (`display_name`, `birth_date`, `country_code`, `onboarding_completed`), `demo_sessions` row with `expires_at = now()+600s`, password grant with the public API key (`sb_publishable_…` preferred, legacy anon JWT fallback; sent only as the `apikey` header, never decoded) | `setSession(refresh_token)`; countdown seeded from `duration_seconds` (not from the browser clock vs. an absolute time) |
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
<!-- Start Demo button → mount this iframe (the web demo is hosted on its own
     Cloudflare Pages hostname; never embed paaxmusic.app or a *.pages.dev preview) -->
<iframe
  id="paax-demo"
  src="https://demo.paaxmusic.app/?demo=1"
  allow="autoplay; encrypted-media; fullscreen"
  referrerpolicy="strict-origin-when-cross-origin"
  style="width:393px;height:852px;border:0;border-radius:48px"></iframe>
```

- The app mints its own session on load (no call from the portfolio needed), shows the real Home, and at zero shows **Demo Session Ended → Restart Demo** by itself.
- Reopening the modal within the ten minutes resumes the same session; the timer is not reset.
- **Lifecycle events** are posted to the parent window as JSON strings; the portfolio can render its own timer from them:

```js
const demoFrame = document.getElementById('paax-demo');
window.addEventListener('message', (e) => {
  // BOTH checks are required: the exact demo origin AND the exact iframe window.
  // The app posts with a wildcard target origin (payload is lifecycle state only,
  // never tokens), so the parent must be the side that filters.
  if (e.origin !== 'https://demo.paaxmusic.app') return;
  if (e.source !== demoFrame.contentWindow) return;
  let m;
  try { m = JSON.parse(e.data); } catch (_) { return; }   // { type: 'paax-demo', event, ... }
  if (!m || m.type !== 'paax-demo') return;
  // event: 'started' {remainingSeconds, expiresAt} | 'tick' {remainingSeconds}
  //        | 'ended' {reason: 'expired'|'signed_out'|'ended'} | 'error' {message}
});
```

- **Requirements on the `demo.paaxmusic.app` host** (Cloudflare Pages, direct upload of `build/web`): send `Content-Security-Policy: frame-ancestors 'self' https://uzielsandoval.com https://www.uzielsandoval.com` (and no `X-Frame-Options: DENY`). Use the **query form `?demo=1`** (the portfolio contract above). On Pages the `/demo` path rewrite is canonicalised to a `308` to `/` (query preserved), and `/index.html` is always `308` to `/` — which is why the service worker is v2. Both files are shipped by `frontend/web/_headers` and `frontend/web/_redirects`, which `flutter build web` copies into the output. Verified on the live host (2026-11-05): CSP allows the `self` ancestor and refuses a foreign origin; TLS certificate `CN=demo.paaxmusic.app` (Google Trust Services), DNS `demo CNAME paax-demo.pages.dev` (proxied), no other DNS record touched.
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
| Railway `paax-api` | `DEMO_ENABLED` | **`false` by default** (unset = disabled, `/v2/demo/*` answers 503 `DEMO_DISABLED`). Set `true` only at activation time; set `false` to kill the feature instantly |
| Railway `paax-api` | `DEMO_SESSION_SECONDS`, `DEMO_RATE_LIMIT_PER_IP`, `DEMO_RATE_LIMIT_WINDOW_SECONDS`, `DEMO_RATE_LIMIT_GLOBAL`, `DEMO_EMAIL_DOMAIN`, `DEMO_DISPLAY_NAME`, `DEMO_WEB_URL` | optional overrides (defaults 600 / 6 / 600 / 120 / `demo.paaxmusic.app` / `Demo Visitor` / `https://paaxmusic.app/?demo=1`). Production currently sets `DEMO_RATE_LIMIT_GLOBAL=20` (temporary, Stage 5) and `DEMO_WEB_URL=https://demo.paaxmusic.app/?demo=1`. |
| Supabase | migration `20261030000000_demo_sessions.sql` | applied to production (2026-11-04) |
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

- **Album header artwork stuck on the placeholder (fixed, shared widget).** `AlbumDetailScreen` first builds the header with the card's artwork URL and swaps to the fetched album URL when data arrives. `AppImage.didUpdateWidget` reset `_canLoad` on that change but never re-requested load permission, and the `VisibilityDetector` only fires on visibility *changes*, so for an already-visible header the new URL was never fetched (diagnostic: zero requests for the header URL, no 429, no errors). Fix: `AppImage` now tracks the last visibility and, when the URL changes while visible, re-requests permission after the frame. Platform-neutral; mobile had masked it on repeat visits via the disk-cache shortcut in `initState`. Verified on three cold album opens. Search artist avatars were only slow: the web image queue is deliberately serial with a 500 ms spacing (429 protection), so a row of avatars takes several seconds; no change.
- `405 HEAD http://127.0.0.1:8000/` in the console: the legacy `youtube_music_data_source` warm-up pings the API root with `HEAD`; FastAPI answers 405. Harmless, pre-existing, same on production.
- With the accessibility semantics overlay enabled, the merged album-row node's tap action resolves to the row's overflow menu instead of play (pointer taps are fine). Minor a11y issue, not visitor-facing.
- Generated desktop registrant files (`linux/`, `windows/`, `macos/` `generated_plugin*`) were touched by the toolchain only to add `connectivity_plus`; noise, not part of the change.

## Testing

- paax-api: `tests/test_demo_sessions.py` — identity minting (flag, confirmed email, random password never returned), independent identities/expiries for two visitors, rollback on token-exchange failure, server-authoritative status/expiry, end marks + deletes, sweep grace window, router create/status/end, per-IP rate limit keyed on the edge-written `X-Real-IP` (forged `CF-Connecting-IP` / `X-Forwarded-For` ignored, missing/malformed identity fails closed, IPv6 per /64), fail-closed without Redis, kill switch, existing routes untouched. Plus `tests/test_cors_origins.py` (allowlist parser, preflight/authenticated requests, anchored local regex, optional Pages-preview regex). PR #8 adds the policy-compliant password generator (5000 generated passwords checked offline, `token_urlsafe` regression, exactly-one retry on `AuthWeakPasswordError`, no password in logs/responses). Full suite: 141 passed (paax-api main `ae08872`).
- Web service worker: `frontend/test/web_sw/custom_service_worker.test.mjs` (`node --test frontend/test/web_sw/`, 15 tests; 10 of them fail against v1 via `PAAX_SW_PATH`).
- Flutter: `test/unit/demo_mode_test.dart` (URL opt-in, never on mobile), `test/unit/demo_session_controller_test.dart` (start, expiry side effects, restart mints a new identity, reload resumes remaining time, reload of an expired session ends, server re-validation wins, sign-out guard, rate-limit error + retry). Full unit+widget suite (worktree, 2026-10-30): 708 passed, 1 failed — `test/widget_test.dart` "App smoke test" fails identically on `main` (pre-existing `path_provider` MissingPluginException in the VM test runner), unrelated to the demo work.
- Browser E2E (puppeteer-core, pointer-only, local stack): see "Flutter Web validation" above — Start → Home → Album → Play → mini player → Search → Artist → Library/Profile → expiry (forced and natural) → Restart → reload; two visitors in two browser profiles see only their own rows.

---

## Production release checklist (2026-11-02)

Runbook files: `docs/runbooks/demo-release/` (`README.md` stage table, `01_migration_audit.sql`,
`02_post_apply_checks.sql`, `03_rollback_demo_guard.sql`, PR texts). Every stage needs an explicit go;
after each stage, verification is reported before the next one starts.

**Preserved and verified before release:** `feat/ui-sculpted-pills` `0cab89c` is the UI baseline; the demo
branch contains it unchanged; the only playback-related differences are the three approved files; auth
controllers, auth screens, the mobile engine, the matching services and the backend playback services are
byte-identical to the baseline.

**Railway `paax-api` variables (stage 3, before the deploy; `DEMO_ENABLED` stays unset until stage 7):**

| Variable | Value |
|---|---|
| `SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_ZqEzyHbIGvHVCGvoSRU6kw_2QKU8dom` (public) |
| `FRONTEND_ORIGINS` | `https://paaxmusic.app,https://www.paaxmusic.app,https://demo.paaxmusic.app,https://uzielsandoval.com,https://www.uzielsandoval.com` (replaces `*`) |
| `DEMO_WEB_URL` | `https://demo.paaxmusic.app/?demo=1` |
| `FRONTEND_ORIGIN_REGEX` | only while testing Pages previews, e.g. `https://[a-z0-9-]+\.<project>\.pages\.dev`; remove afterwards |
| `DEMO_ENABLED` | **unset / `false`** at stage 3; `true` only at stage 7; `false` is the instant kill switch |
| unchanged | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `REDIS_URL` |

**Migration (stage 4):** preflight `01_migration_audit.sql`, backup per `00_backup_free_plan.md` (restore proof via
`06_backup_fingerprint.sql`), then apply `04_apply_option_a.sql` **by itself, in one transaction**. The migration is
fail-closed: it enables `pg_cron`, schedules `paax_demo_cleanup` and asserts the job is active; if any of that fails
nothing is applied (verified in staging, see `docs/runbooks/demo-release/AUDIT_2026-11-02.md`). Never
`supabase db push` (production history uses MCP-assigned versions). Then `02_post_apply_checks.sql` plus a real
login, a Home/Library load and one throwaway registration from the mobile app. The optional history record is
deferred until the application method is final. Rollback: `05_emergency_detach_guard.sql` (seconds) or
`03_rollback_demo_guard.sql` (full; pg_cron stays installed by decision).

**Guard safety review:** the hook returns immediately for any JWT without `app_metadata.paax_demo=true`
(anon, service role, every real user) using only JSON operations on the claims; claim parsing is wrapped so a
malformed value cannot raise; the only raises are the intentional PT401/PT403 for demo identities. Cost for
real traffic: one `current_setting` + a few jsonb lookups per request.

**Rate limiter behind the real proxies (paax-api PR #7, main `148cc31`):** the per-visitor bucket is keyed
ONLY on `X-Real-IP`. Railway's public HTTP edge replaces any caller-sent `X-Real-IP`/`X-Forwarded-For` and derives
`X-Real-IP` from `CF-Connecting-IP` only when the TCP peer is Cloudflare, so through Cloudflare it is the visitor
and on the direct-to-Railway-edge path (Host-header bypass, which exists) it is the caller's real socket address.
`CF-Connecting-IP` and `X-Forwarded-For` are not read (Cloudflare itself also rejects a client-sent
`CF-Connecting-IP` with 403 error 1000). Missing or malformed identity → 503 `DEMO_UNAVAILABLE`, nothing minted,
address never logged. Creation also fails closed when Redis is missing or down (`DEMO_REQUIRE_RATE_LIMITER=true`).
Known limitation: Railway private networking bypasses the edge sanitisation; Railway calls this current behaviour,
not a contract. Live verification of the header path is part of Stage 5 activation (expect 429 on the 7th create
from one browser, never 503).

## Production status (2026-11-06)

| Component | State |
|---|---|
| Frontend `main` | `f1868b1` (PR #103 merged: service worker v2) |
| Web host | Cloudflare Pages project `paax-demo`, production deployment built from `f1868b1` (release dir `web-demo-f1868b1`, `SHA256SUMS.txt` recorded), custom domain `https://demo.paaxmusic.app` **active** (Stage 4C), CSP `frame-ancestors` verified positive and negative |
| paax-api `main` | `ae08872` (PR #7 trusted-IP limiter, PR #8 password policy), Railway deployment ACTIVE |
| Railway variables | `DEMO_ENABLED=false` (kill switch, demo disabled), `DEMO_REQUIRE_RATE_LIMITER=true`, `DEMO_RATE_LIMIT_GLOBAL=20` (temporary), `DEMO_WEB_URL`, `FRONTEND_ORIGINS` allowlist, `SUPABASE_PUBLISHABLE_KEY`; secrets unchanged |
| Supabase | migration applied 2026-11-04; `paax_demo_cleanup` cron active; guard returns `401 PT401 DEMO_SESSION_EXPIRED` for ended demo JWTs |
| Normal-user baseline | 5 `auth.users`, 5 `profiles`, 30 `playlists`, unchanged across every activation |

**Stage 5 (2026-11-05, controlled activation):** real browser session minted with `paax_demo=true` / 600 s; Home, Search,
album, YouTube iframe playback, mini/full player, pause/resume/next; 7th creation from one address → `429 DEMO_RATE_LIMITED`
with `Retry-After`; forged `X-Forwarded-For` / `X-Real-IP` still 429, forged `CF-Connecting-IP` → Cloudflare 403; reload does
not mint; RLS isolation (own row only); ended JWT rejected by the guard; natural expiry → "Demo Session Ended" → Restart;
cron deleted the expired identities within ~2 min. Finding: 2 of 8 creations failed with `502 DEMO_IDENTITY_CREATE_FAILED`
(`AuthWeakPasswordError`: `token_urlsafe` passwords lack symbols ~25 % of the time) → fixed in Stage 5.1 (PR #8).

**Stage 5.2 (2026-11-06, final controlled validation, `DEMO_ENABLED=true` from 06:27 to shutdown UTC):** 6 of 6 scripted
creations from the desktop network returned 201 (no 502, no weak-password error), each identity carried
`app_metadata.paax_demo=true` and `demo_client`, a confirmed `demo-…` email and a matching `demo_sessions` row; the 7th
creation → 429 (`Retry-After 586`); `X-Forwarded-For`, `X-Real-IP`, `Forwarded` and `True-Client-IP` forgeries all 429
(bucket unchanged); all six ended explicitly (200) and were removed. Browser smoke test on the live host: start without
registration, Home, Search, album pages, reload resumes the same session, natural expiry → "Demo Session Ended", Restart Demo
mints a new identity, Profile → Log out ends it (`ended` / `signed_out` posted to the parent). **Playback did not start**: every
track returned YouTube player error 150 (`errorCode: "auth"`) — see Known limitations. Shutdown: `DEMO_ENABLED=false` redeployed,
`POST /v2/demo/sessions` → 503, all test identities removed by the end-or-cleanup path, normal-user counts unchanged.

**Open blocker — YouTube embedded playback in the web demo (found 2026-11-06, no code changed):** the hidden
`youtube_player_iframe` frame carries the `credentialless` attribute. Since 2026-11-06 YouTube answers that player with
`PlayerError 150` / `errorCode: "auth"` for every video (label-owned and independent uploads alike), while an identical
copy of the same frame template without `credentialless`, on the same origin with the same player parameters and the
same video ids, plays normally. Playback worked on 2026-11-05 with the byte-identical build, so this is a YouTube-side
policy change. Any fix touches the playback engine (`core/playback/playback_engine_web.dart` / the package's web
template) and requires separate explicit approval.

## Known limitations

- Demo identities see the same Home a brand-new real user sees (Trending / Recently added + whatever they follow during the session). No follows are seeded: fake taste would be indistinguishable from real recommendation logic.
- `https://paaxmusic.app` (apex / `www`) still answers Cloudflare 522/525 (origin down, pre-existing and untouched). The demo does not depend on it: the embed target is `https://demo.paaxmusic.app`, served from Cloudflare Pages. See [current-state](../current-state.md).
- The profile email shown in Profile is the generated `demo-…@demo.paaxmusic.app` address.
- Label-owned YouTube videos refuse embedding from loopback/IP origins (error 150); the demo must run from a real domain (`demo.paaxmusic.app`). Real-domain playback was verified on 2026-11-05 (YouTube iframe, mini/full player, pause/resume/next) but **failed on 2026-11-06 with error 150 for every video** — see the open blocker under [Production status](#production-status-2026-11-06).
- The Random Access Memories album page intermittently shows no track list (observed once in Stage 5 and recorded in Stage 5.2). Catalog/UI issue, not playback; not modified during the demo release.
- Per-IP bucket independence between two physically different networks has not yet been observed live (needs a second connection, e.g. a phone on mobile data); the trusted-header path is covered by unit tests and by the forged-header checks below.
- Cold album pages (first ingestion of an album) can take 15–20 s before track rows appear.
