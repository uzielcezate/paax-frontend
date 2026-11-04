# Deployment

> **Purpose**: Step-by-step deployment instructions for every environment. Agents and humans can follow this guide to deploy safely and predictably.
> **Update when**: The deployment process changes, new environments are added, or infrastructure changes.

---

## Environments

| Environment | Purpose | Branch | URL |
|-------------|---------|--------|-----|
| Development | Local dev (Flutter + services on `localhost`) | any | `http://127.0.0.1:8000` (api), `:8080` (stream) |
| LAN test | On-device testing over LAN | any | `http://<PC-LAN-IP>:8000` |
| Production | Live users | `main` | `api.paaxmusic.app`, `resolver.paaxmusic.app`, `stream.paaxmusic.app`, `paaxmusic.app` |

There is **no separate staging environment** and **no CI/CD pipeline** — deploys are push-to-deploy on Railway/Cloudflare. Adding staging + CI is a backlog item ([IDEAS.md](IDEAS.md)).

---

## Pre-Deployment Checklist

Before deploying to **production**, verify:

- [ ] `flutter analyze` is clean and `dart format` applied (the only automated gates — see [testing.md](testing.md))
- [ ] No uncommitted changes; on the `main` branch
- [ ] Environment variables set on the target service (see [environment.md](environment.md))
- [ ] `docs/release-notes.md` and `docs/CHANGELOG.md` updated
- [ ] `docs/current-state.md` updated
- [ ] For an Android release: version bumped in `local.properties`, and a **real signing config** used (⚠️ currently release builds sign with **debug keys** — see [Known Gaps](#known-gaps--gotchas))

---

## Local Development Setup

```bash
# 1. Clone
git clone https://github.com/uzielcezate/Paax.git && cd Paax

# 2a. Metadata backend (paax-api)
cd paax-api
python -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
# Optional: place oauth.json here for authenticated endpoints; set REDIS_URL for caching
uvicorn main:app --reload --host 0.0.0.0 --port 8000
# Health: http://127.0.0.1:8000/health

# 2b. (Optional) Stream proxy (paax-stream) — not needed for IFrame playback
cd ../paax-stream
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080

# 3. Flutter app
cd ../frontend
flutter pub get
flutter run --dart-define=ENV=local              # points at 127.0.0.1:8000 / :8080
# Android emulator reaches host via 10.0.2.2 (CORS already allows it)
```

**On-device LAN testing:**
```bash
# find your PC IPv4 (ipconfig / ip addr), allow port 8000 through the firewall
flutter run --dart-define=ENV=lan --dart-define=LAN_IP=192.168.1.10
```

---

## Production Deployment

### Python services (Railway)

All three Python services deploy on **Railway** with the **NIXPACKS** builder. Each has a `railway.json` + `Procfile`. Deploy = push to the service's tracked branch (or trigger a redeploy in the Railway dashboard).

| Service | Root dir | Start command | Healthcheck | Domain |
|---------|----------|---------------|-------------|--------|
| paax-api | `paax-api/` | `uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}` | none declared | `api.paaxmusic.app` |
| paax-stream | `paax-stream/` | `uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}` | `/health` | `resolver.paaxmusic.app` |
| backend (legacy) | `backend/` | `uvicorn main:app --host 0.0.0.0 --port $PORT` | none | (retired) |

All use `restartPolicyType=ON_FAILURE`, `restartPolicyMaxRetries=5`. Set env vars (see [environment.md](environment.md)) and attach a Redis plugin per service as needed.

> `paax-api` and `paax-stream` each contain their own `.git` directory — they are effectively separate repos (`uzielcezate/paax-api`, `uzielcezate/paax-stream`) vendored into this monorepo tree. Deploy them from their own repos/roots on Railway.

### Cloudflare Worker

```bash
cd cloudflare-worker
npx wrangler deploy        # publishes worker.js to stream.paaxmusic.app
```
The route binding (`stream.paaxmusic.app/*`) is configured in the Cloudflare dashboard (commented out in `wrangler.toml`). No secrets to set.

### Web app (PWA/TWA)

```bash
cd frontend
flutter build web --dart-define=ENV=prod
# Deploy build/web/ to the host serving paaxmusic.app (static hosting / Cloudflare Pages)
```
The web build doubles as the **TWA** wrapped Android app: `.well-known/assetlinks.json` (digital asset links, SHA-256 cert fingerprint) + an offline-first service worker enable Trusted Web Activity cold-start. Keep `assetlinks.json` in sync with the signing certificate.

### Portfolio demo web build — Cloudflare Pages (`demo.paaxmusic.app`, prepared 2026-10-30, not yet deployed)

Target architecture: portfolio `uzielsandoval.com` (Vercel) embeds `https://demo.paaxmusic.app/?demo=1` (Cloudflare Pages) → `api.paaxmusic.app` (Railway) → Supabase. See [features/demo-mode.md](features/demo-mode.md).

```bash
cd frontend
flutter build web --release \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=https://api.paaxmusic.app
# Output: build/web/  (includes web/_headers and web/_redirects verbatim)
```

- `web/_headers` sets `Content-Security-Policy: frame-ancestors 'self' https://uzielsandoval.com https://www.uzielsandoval.com` (the ONLY origins allowed to frame the app), `Permissions-Policy` autoplay for YouTube, and `no-cache` for `index.html` + service workers. Edit the `frame-ancestors` list if the portfolio origin changes.
- `web/_redirects` is the SPA fallback (`/demo` and deep links serve `index.html`).
- **Create the Pages project** (dashboard → Workers & Pages → Create → Pages → *Direct Upload*, or `npx wrangler pages project create paax-demo`), then publish a **preview** first:
  ```bash
  npx wrangler pages deploy build/web --project-name paax-demo --branch preview
  # → https://preview.paax-demo.pages.dev  (temporary preview domain for verification)
  ```
  Verify on the preview URL: the app boots, `?demo=1` starts a session, playback works inside an `<iframe>` served from an allowed origin, and `curl -I` shows the CSP header.
- **Production** (after approval): `npx wrangler pages deploy build/web --project-name paax-demo --branch main`, then add the custom domain `demo.paaxmusic.app` in Pages → Custom domains (Cloudflare creates the CNAME automatically because the zone is on Cloudflare). This does **not** touch the apex `paaxmusic.app` record.
- **paax-api CORS**: replace the wildcard with `FRONTEND_ORIGINS=https://paaxmusic.app,https://www.paaxmusic.app,https://demo.paaxmusic.app,https://uzielsandoval.com,https://www.uzielsandoval.com`. While testing a Pages preview add `FRONTEND_ORIGIN_REGEX=https://[a-z0-9-]+\.<pages-project>\.pages\.dev` and remove it once the custom domain is live. Mobile apps are unaffected (no `Origin` header).
- **Supabase Auth**: add `https://demo.paaxmusic.app` to Authentication → URL Configuration → Redirect URLs only if password-recovery links should ever land on the web build; the demo itself never sends e-mail.
- **Browser session behaviour inside the iframe**: the Supabase session is persisted in the iframe origin's `localStorage`. Chrome/Firefox partition third-party storage per top-level site, so a visitor's demo session survives closing/reopening the portfolio modal (same remaining time) but is not shared with a direct visit to `demo.paaxmusic.app`. Safari with "Prevent cross-site tracking" may block third-party storage entirely; the app then still works but a reload inside the iframe mints a new session.

### Android (native APK/AAB)

```bash
cd frontend
flutter build appbundle --dart-define=ENV=prod   # or: flutter build apk
```
⚠️ **Blocking gap**: `android/app/build.gradle` uses `signingConfig signingConfigs.debug` for release, and `applicationId` is still `com.beaty.music.beaty`. A real keystore + a Paax `applicationId` are required before a Play Store release. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) / [TECH_DEBT.md](TECH_DEBT.md).

---

## Database Migrations

**Not applicable** — there is no server database. Client-side Hive "migrations" are imperative de-dup passes that run automatically at app startup (`HiveStorage.init()`), require no deploy step, and are described in [database.md](database.md).

---

## Rollback Procedure

1. **Railway**: redeploy the previous successful deployment from the service's Deployments tab (or revert the commit and push).
2. **Cloudflare Worker**: `wrangler rollback` or redeploy the prior `worker.js`.
3. **Web/PWA**: redeploy the previous `build/web/` artifact.
4. **Android**: ship a new build (store releases can't be un-published, only superseded); halt a staged rollout in the Play Console.
5. No DB rollback needed (no server DB). Client data is unaffected by server rollbacks.

---

## Infrastructure as Code

Minimal. Per-service config is committed: `railway.json` + `Procfile` (Railway), `wrangler.toml` (Cloudflare). There is no Terraform/Pulumi; DNS and Railway/Cloudflare project settings are managed in their dashboards.

---

## Monitoring After Deploy

- [ ] `GET /health` returns `200` on paax-api and paax-stream
- [ ] `GET /cache/status` shows Redis reachable (paax-api)
- [ ] A `/v2/search?q=test` returns tracks with populated `playback.videoId`
- [ ] Worker resolve (`stream.paaxmusic.app/<videoId>`) returns a `url`
- [ ] App: play a track end-to-end; media notification appears (Android)

There is no error-tracking (Sentry) or APM configured — adding observability is a backlog item ([performance.md](performance.md), [IDEAS.md](IDEAS.md)). Cloudflare Worker has `[observability] enabled=true`.

---

## Known Gaps & Gotchas

- Release Android builds sign with **debug keys**; `applicationId` still `com.beaty.music.beaty`.
- No CI, no staging, no automated tests as a merge gate.
- The Spanish deployment walkthrough for the legacy backend lives at [`RAILWAY_DEPLOY_STEPS_ES.txt`](RAILWAY_DEPLOY_STEPS_ES.txt) (references the old `beaty.up.railway.app`).
- `usesCleartextTraffic=true` in the Android manifest (needed for LAN/HTTP dev) ships to production — revisit before store release.

---

*Last updated: 2026-07-16*
