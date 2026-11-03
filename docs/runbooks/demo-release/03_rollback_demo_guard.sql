-- PAAX demo guard ROLLBACK (production). Run top to bottom; each statement is independent.
-- Step 1 alone removes every request-path effect within one PostgREST config reload (seconds).
-- Tested on the local Supabase CLI stack (same Postgres 17 / PostgREST v16 majors).

-- 1. Detach the pre-request hook (immediate effect on all API traffic)
alter role authenticator reset pgrst.db_pre_request;
notify pgrst, 'reload config';

-- 2. Stop the sweeper
select cron.unschedule('paax_demo_cleanup');

-- 3. Drop the demo-only functions and table (cascade removes policies/grants)
drop function if exists private.demo_cleanup(int, int);
drop function if exists public.paax_pre_request();
drop function if exists public.demo_session_status();
drop table if exists public.demo_sessions;

-- 4. Remove any demo identities that were minted (cascades wipe their profile/library rows)
delete from auth.users where (raw_app_meta_data->>'paax_demo') = 'true';

-- 5. Verify
select rolconfig from pg_roles where rolname = 'authenticator';                     -- no pgrst.db_pre_request
select count(*) as demo_jobs from cron.job where jobname = 'paax_demo_cleanup';     -- 0
select to_regclass('public.demo_sessions') as demo_sessions_table;                  -- null
-- Re-run the baseline counts from 01_migration_audit.sql step 5: must be unchanged.
