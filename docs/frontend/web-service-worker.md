# PAAX Web — custom service worker

File: `frontend/web/custom_service_worker.js` (copied verbatim into `build/web/` by `flutter build web`).
Tests: `frontend/test/web_sw/custom_service_worker.test.mjs` — run with `node --test frontend/test/web_sw/` (Node ≥ 20, no dependencies).

## What it does

- Cache-first app shell so the Flutter UI starts instantly and works offline (TWA requirement).
- Navigation requests (any path, including `/?demo=1`, `/demo` and deep links) are answered with the cached shell, so SPA routing never depends on the host's redirect rules.
- JS, assets, icons and CanvasKit are cache-first with background revalidation. API calls are never cached.
- Cache namespace: `paax-app-shell-v2`. `activate` deletes every other `paax-app-shell-*` cache and claims open clients.

## Why v2 (Cloudflare Pages incident, 2026-11-05)

Cloudflare Pages canonicalises `/index.html` with a `308` redirect to `/`. The v1 worker pre-cached `./index.html`, so the stored entry was a response obtained through a redirect (`Response.redirected === true`). Browsers reject a redirected response when a service worker returns it for a navigation, which produced `ERR_FAILED` on every visit after the first (confirmed in Chrome against a local Pages-like server and against `paax-demo.pages.dev`).

v2 rules:

- The shell is stored under the canonical root `./` only; `./index.html` is never requested or cached.
- A navigation shell is used only if it is `ok`, `redirected === false`, not opaque, and `text/html`. Anything else found in the slot is deleted and refetched; if the root itself does not yield a usable shell the original request is passed to the network untouched.
- Asset entries are written only for `ok`, non-redirected, non-opaque responses.
- Every served shell is revalidated in the background, so a new release reaches returning users on their next visit without clearing site data.

## Upgrade behaviour for clients stuck on v1

The old worker keeps answering until the browser fetches the new script. On the first reload after a v2 deploy the old worker may still fail; the update is installed in parallel and the second reload succeeds. IndexedDB, cookies and local storage are untouched; only the `paax-app-shell-v1` cache is removed.

## Changing it

Bump `CACHE_NAME` whenever the caching rules change, keep the tests green, and verify in a real browser: first visit, reload, repeated reloads, `/?demo=1`, deep link, offline reload, and the v1 → v2 recovery path.
