# PAAX Demo — production release runbook

Release candidate: `feat/ui-sculpted-pills` `0cab89c` (V3/V4 UI) + `worktree-web-demo-mode`
(demo, rebased on top) + paax-api `feat/demo-sessions`. Nothing in this runbook is executed
without an explicit go for that stage; after every stage, stop and report the verification.

Files: `01_migration_audit.sql` (before apply), `02_post_apply_checks.sql` (after apply),
`03_rollback_demo_guard.sql` (rollback, any time). The full checklist with checkpoints lives
in `docs/features/demo-mode.md` → "Production release checklist".

## Production topology facts used below (observed 2026-11-02, read-only)

- `https://api.paaxmusic.app` answers with `Server: cloudflare` + `x-railway-edge`: client →
  Cloudflare → Railway edge → paax-api. The demo rate limiter therefore keys on
  `CF-Connecting-IP`, falling back to the rightmost `X-Forwarded-For` hop (never the first).
- The limiter is Redis-backed (`REDIS_URL` is set on Railway) and degrades OPEN if Redis is
  unavailable — the global cap and the per-IP cap are then not enforced, by design.
- `https://demo.paaxmusic.app` already resolves through Cloudflare and returns 525 (no valid
  origin yet). Attaching it as a Pages custom domain replaces that record.
- `https://paaxmusic.app` (apex) is down (Cloudflare 522/525); the demo does not depend on it.

## Stage order and gates (summary)

| Stage | Action | Gate to pass before the next stage | Rollback |
|---|---|---|---|
| 0 | Device QA of V3/V4 | your sign-off | n/a |
| 1 | PR + merge `feat/ui-sculpted-pills` → `main` | CI/analyzer green; no web/demo files touched | revert merge commit |
| 2 | PR + merge `worktree-web-demo-mode` → `main` | `flutter analyze` 0 errors, 782 tests (1 pre-existing failure) | revert merge commit |
| 3 | PR + merge paax-api `feat/demo-sessions`; set Railway vars WITHOUT `DEMO_ENABLED`; deploy | `/health` 200; `POST /v2/demo/sessions` → 503 `DEMO_DISABLED`; mobile app still works; preflight from `https://paaxmusic.app` gets ACAO | redeploy previous Railway deployment; restore `FRONTEND_ORIGINS=*` if a legitimate origin was missed |
| 4 | `01_migration_audit.sql` (preflight) → `00_backup_free_plan.md` (dump + restore proof + `06_backup_fingerprint.sql`) → `04_apply_option_a.sql` (one transaction, fail-closed: no pg_cron / no job ⇒ nothing applied) → `02_post_apply_checks.sql` | hook attached, cron job active AND executing, real login + registration unaffected; history record deferred | `05_emergency_detach_guard.sql` (seconds) / `03_rollback_demo_guard.sql` (full; pg_cron stays installed) |
| 5 | Cloudflare Pages project + preview upload of `frontend/build/web` | preview serves app; Start shows a clean "unavailable" (API 503) | delete preview |
| 6 | Attach `demo.paaxmusic.app` | HTTPS 200, `_headers` CSP present, `/demo` falls back to shell | detach domain |
| 7 | Railway `DEMO_ENABLED=true` | `POST /v2/demo/sessions` from the demo origin → 201; `/me` → `active:true` | set `DEMO_ENABLED=false` (instant kill switch) |
| 8 | E2E on `https://demo.paaxmusic.app/?demo=1` incl. a label-owned track | playback real; expiry; restart; normal `/` shows login | `DEMO_ENABLED=false` |
| 9 | Portfolio iframe | visible on `uzielsandoval.com`; remove `FRONTEND_ORIGIN_REGEX` if used | remove iframe |

Do **not** use `supabase db push` unless the audit shows the recorded history equals the 30 repo
filenames exactly; otherwise apply the single new file by itself.
