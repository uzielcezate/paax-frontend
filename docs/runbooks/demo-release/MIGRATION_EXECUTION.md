# Demo migration — final backup and execution instructions (Option A: pg_cron)

Status: prepared, **not executed**. Every step below waits for the explicit go. Expected wall time: 20–30 minutes.
Nothing here touches the mobile app, authentication flows, the UI or the playback engine; the migration adds
objects and one role setting, and the pre-request hook is a no-op for every non-demo JWT.

## Step 0 — Decide and freeze (you)
- Option A confirmed: `pg_cron` will be enabled by the migration (`create extension if not exists pg_cron with schema pg_catalog`).
- No other production change is in flight (no Railway deploy, no Pages deploy) during steps 1–4.

> Windows: Steps 1–2 are automated by `windows/Backup-Production.ps1` + `windows/Verify-Restore.ps1`
> (see `windows/README.md`, which also states the PASS/FAIL criteria for authorizing Step 3).

## Step 1 — Preflight (read-only, SQL editor or psql): `01_migration_audit.sql` sections C–F
Pass criteria: `private` schema present; `auth.users.raw_app_meta_data` is jsonb; the 5 `profiles` columns exist;
a signup trigger exists on `auth.users`; no user-data table without RLS; `authenticator.rolconfig` has no
`pgrst.db_pre_request`; `pg_available_extensions` lists `pg_cron` with `installed_version` null;
`shared_preload_libraries` contains `pg_cron`; current database is `postgres`; baseline 5 / 5 / 30 / 0 demo users.
Any mismatch → stop and report; do not continue.

## Step 2 — Backup: `00_backup_free_plan.md` sections 1–2
Pass criteria: six dump files exist; `06_backup_fingerprint.sql` output from production and from the local restore
is identical (exact counts and md5 lines, auth data included); storage object contents exported and verified
(`windows/Export-Storage.ps1`, MD5 = eTag for every object); folder encrypted at rest (`windows/Protect-Backup.ps1`).
Done 2026-11-03 — see `AUDIT_2026-11-02.md` addenda. Keep the folder private.

## Step 3 — Apply (one transaction): `04_apply_option_a.sql`
- **Selected application method (Windows):** `windows/Run-ProdSql.ps1 -Kind apply -Confirm 'APPLY-DEMO-MIGRATION'`
  — psql inside the isolated container over the session pooler as role `postgres`, URI over stdin, output saved
  (scrubbed) under `PaaxBackups\release-log\`. `ON_ERROR_STOP=1`: any error ends psql before `commit;` and the
  connection close rolls everything back. Rehearsed end to end on an exact production clone (see
  `AUDIT_2026-11-02.md` → "full rehearsal"). The SQL-editor paste remains the manual fallback.
- It is the committed migration file verbatim between `begin;` and `commit;`. Paste the whole file, run once.
- **Fail-closed.** The migration no longer tolerates a missing sweeper: `create extension pg_cron` is a plain
  statement (no exception swallowing), the job is scheduled, and an explicit assertion re-reads `cron.job` and
  raises if `paax_demo_cleanup` is not present and active with the expected command. Any of these failing aborts
  the single transaction, so no table, function or hook is left behind. Verified in staging (see
  `AUDIT_2026-11-02.md` → "Fail-closed verification"): pg_cron not loadable → `ERROR: pg_cron can only be loaded
  via shared_preload_libraries`, state unchanged; `cron.schedule()` failing → state unchanged; `cron.schedule()`
  returning an id with no active job → `ERROR: paax_demo_cleanup job was not scheduled; aborting the demo
  migration`, state unchanged; clean apply → table, 3 functions, extension, active job, hook.
- Expected output: no `ERROR` lines. One harmless `NOTICE: policy ... does not exist, skipping` is normal.
- If the editor reports an error, the transaction has rolled back and production is unchanged. Report the error
  text; do not retry until the cause is understood (most likely candidates: pg_cron not permitted on the project,
  or a privilege refusal on `alter role authenticator`).
- `alter role authenticator set …` + `notify pgrst, 'reload config'` make the hook effective for new PostgREST
  connections within seconds; no API restart is needed. If in doubt: Dashboard → Settings → API → Restart.

## Step 4 — Verify: `02_post_apply_checks.sql` (all 7 sections)
Pass criteria listed inline. Section 7 includes the real-user functional checks from your phone and the
`genres` read with the publishable key. Wait two minutes and confirm `cron.job_run_details` shows successful runs.

## Step 5 — History record: DEFERRED
No row is inserted into `supabase_migrations.schema_migrations` in this stage. Whether and how to record
`20261030000000 demo_sessions` is decided after the application method is final (SQL editor vs MCP
`apply_migration`, which records it automatically) and is a separate, explicitly approved step. The two
production-only entries `profiles_add_first_last_name` and `username_available_rpc` are left exactly as they are;
no history row is rewritten or repaired during this release.

## pg_cron after a rollback: decision
`03_rollback_demo_guard.sql` unschedules the job and removes every demo object but **leaves the pg_cron extension
installed**. Reasons: with no job scheduled it does nothing and costs nothing; dropping it is irreversible for any
other future job and is a separate decision; keeping it makes a re-apply after a fixed problem a pure re-run of
`04_apply_option_a.sql`. If you want it gone after a rollback, run `drop extension pg_cron;` as its own reviewed
step (it fails safely if any job still references it).

## Rollback at any point
- Emergency (seconds, keeps objects): `05_emergency_detach_guard.sql`.
- Full: `03_rollback_demo_guard.sql` (detach hook → unschedule job → drop functions/table → delete any demo users →
  verify baseline 5 / 5 / 30). `pg_cron` itself stays enabled after a rollback; dropping the extension is a separate
  decision (`drop extension pg_cron;`) and is not required for safety — with no job scheduled it does nothing.

## What is NOT done in this stage
- No `supabase db push`, no rewrite of existing `schema_migrations` rows.
- No Railway change (the API keeps `DEMO_ENABLED` unset and answers 503 on `/v2/demo/*`).
- No Cloudflare Pages or DNS change.
