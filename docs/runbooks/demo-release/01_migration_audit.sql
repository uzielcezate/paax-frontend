-- PAAX production migration-history audit (READ-ONLY). Run in the Supabase SQL editor
-- (project jecgmiuypuathhvjuhea) or via the Supabase MCP execute_sql.
-- Compare query 1 with the 31 files in supabase/migrations/ (30 existing + 20261030000000_demo_sessions).
-- Decision rule: if the recorded versions are NOT exactly the 30 repo filenames, do NOT run
-- `supabase db push` (it would try to re-apply every unrecorded file). Apply the single new
-- migration file by itself instead (SQL editor or MCP apply_migration with name demo_sessions).

-- 1. Recorded migration history (what `supabase db push` would diff against)
select version, name, inserted_at
from supabase_migrations.schema_migrations
order by version;

-- 2. Demo objects must be ABSENT before applying
select
  to_regclass('public.demo_sessions')                                   as demo_sessions_table,
  (select count(*) from pg_proc where proname = 'paax_pre_request')     as pre_request_fn,
  (select count(*) from pg_proc where proname = 'demo_cleanup')         as cleanup_fn,
  (select count(*) from pg_proc where proname = 'demo_session_status')  as status_fn,
  (select rolconfig from pg_roles where rolname = 'authenticator')      as authenticator_config;

-- 3. pg_cron availability (the migration schedules the sweeper only if the extension exists)
select extname, extversion from pg_extension where extname = 'pg_cron';

-- 4. There must be no existing pre-request hook the migration would overwrite
select coalesce(current_setting('pgrst.db_pre_request', true), '(none)') as current_pre_request;

-- 5. Baseline counts to compare after rollback (must be unchanged)
select
  (select count(*) from auth.users)      as users,
  (select count(*) from public.profiles) as profiles,
  (select count(*) from public.playlists) as playlists;
