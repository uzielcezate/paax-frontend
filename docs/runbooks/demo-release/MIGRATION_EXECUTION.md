# Demo migration — final backup and execution instructions (Option A: pg_cron)

Status: prepared, **not executed**. Every step below waits for the explicit go. Expected wall time: 20–30 minutes.
Nothing here touches the mobile app, authentication flows, the UI or the playback engine; the migration adds
objects and one role setting, and the pre-request hook is a no-op for every non-demo JWT.

## Step 0 — Decide and freeze (you)
- Option A confirmed: `pg_cron` will be enabled by the migration (`create extension if not exists pg_cron with schema pg_catalog`).
- No other production change is in flight (no Railway deploy, no Pages deploy) during steps 1–4.

## Step 1 — Preflight (read-only, SQL editor): `01_migration_audit.sql` sections C–F
Pass criteria: `private` schema present; `auth.users.raw_app_meta_data` is jsonb; the 5 `profiles` columns exist;
a signup trigger exists on `auth.users`; no user-data table without RLS; `authenticator.rolconfig` has no
`pgrst.db_pre_request`; `pg_available_extensions` lists `pg_cron` with `installed_version` null;
`shared_preload_libraries` contains `pg_cron`; current database is `postgres`; baseline 5 / 5 / 30 / 0 demo users.
Any mismatch → stop and report; do not continue.

## Step 2 — Backup: `00_backup_free_plan.md` sections 1–2
Pass criteria: five dump files exist; local restore prints `5|5|30`. Keep the folder private.

## Step 3 — Apply (SQL editor, one transaction): `04_apply_option_a.sql`
- It is the committed migration file verbatim between `begin;` and `commit;`. Paste the whole file, run once.
- Expected notices: none, or `pg_cron not available (...)` — if you see that notice, pg_cron was NOT enabled and the
  job was NOT scheduled; the rest still applied. Report it (we would then fall back to Option B's API sweep or retry
  after enabling pg_cron from Dashboard → Database → Extensions, your call).
- If the editor reports an error, the transaction has rolled back and production is unchanged. Report the error text.
- `alter role authenticator set …` + `notify pgrst, 'reload config'` make the hook effective for new PostgREST
  connections within seconds; no API restart is needed. If in doubt: Dashboard → Settings → API → Restart.

## Step 4 — Verify: `02_post_apply_checks.sql` (all 7 sections)
Pass criteria listed inline. Section 7 includes the real-user functional checks from your phone and the
`genres` read with the publishable key. Wait two minutes and confirm `cron.job_run_details` shows successful runs.

## Step 5 — Record (optional hygiene, after a green step 4)
```sql
insert into supabase_migrations.schema_migrations (version, name)
values ('20261030000000', 'demo_sessions')
on conflict do nothing;
```
This keeps the history table consistent with the repo file for future audits. It does not rewrite existing rows.
(The two production-only entries `profiles_add_first_last_name` and `username_available_rpc` are a separate,
pre-existing documentation debt — see AUDIT_2026-11-02.md §1 — and are not touched.)

## Rollback at any point
- Emergency (seconds, keeps objects): `05_emergency_detach_guard.sql`.
- Full: `03_rollback_demo_guard.sql` (detach hook → unschedule job → drop functions/table → delete any demo users →
  verify baseline 5 / 5 / 30). `pg_cron` itself stays enabled after a rollback; dropping the extension is a separate
  decision (`drop extension pg_cron;`) and is not required for safety — with no job scheduled it does nothing.

## What is NOT done in this stage
- No `supabase db push`, no rewrite of existing `schema_migrations` rows.
- No Railway change (the API keeps `DEMO_ENABLED` unset and answers 503 on `/v2/demo/*`).
- No Cloudflare Pages or DNS change.
