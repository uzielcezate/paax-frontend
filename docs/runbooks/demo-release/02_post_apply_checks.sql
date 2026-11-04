-- PAAX demo migration POST-APPLY verification (READ-ONLY). Run immediately after 04_apply_option_a.sql.
-- All checks must pass before the Cloudflare stage; DEMO_ENABLED stays unset until stage 7.

-- 1. Objects exist
select to_regclass('public.demo_sessions') as demo_sessions_table;                                  -- public.demo_sessions
select proname, prosecdef from pg_proc where proname in ('paax_pre_request', 'demo_cleanup', 'demo_session_status') order by 1;
--   expect 3 rows, prosecdef = t for all three

-- 2. demo_sessions is locked down: RLS on, authenticated may only SELECT, anon nothing
select relrowsecurity from pg_class where oid = 'public.demo_sessions'::regclass;                  -- t
select grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'public' and table_name = 'demo_sessions' order by 1, 2;                       -- authenticated: SELECT only; no anon row
select policyname, cmd, roles from pg_policies where tablename = 'demo_sessions';                   -- one SELECT policy (own row)

-- 3. Guard attached to the API role (effective for new PostgREST connections after the reload)
select rolconfig from pg_roles where rolname = 'authenticator';                                     -- contains pgrst.db_pre_request=public.paax_pre_request
select grantee, privilege_type from information_schema.routine_privileges
 where routine_schema = 'public' and routine_name = 'paax_pre_request' order by 1;                   -- anon, authenticated, service_role: EXECUTE

-- 4. Cleanup privileges: only postgres (owner / cron) may execute the sweeper
select grantee, privilege_type from information_schema.routine_privileges
 where routine_schema = 'private' and routine_name = 'demo_cleanup' order by 1;                      -- expect no anon / authenticated / PUBLIC rows

-- 5. pg_cron (Option A)
select extname, extversion, extnamespace::regnamespace from pg_extension where extname = 'pg_cron'; -- 1 row, schema pg_catalog
select jobid, jobname, schedule, command, username, active from cron.job where jobname = 'paax_demo_cleanup';
--   expect: * * * * * | select private.demo_cleanup(); | postgres | t
-- after >= 2 minutes:
select status, return_message, start_time from cron.job_run_details
 where jobid = (select jobid from cron.job where jobname = 'paax_demo_cleanup')
 order by start_time desc limit 3;                                                                  -- status succeeded, return_message "1 row" (function returned 0)

-- 6. Nothing happened to real data
select
  (select count(*) from auth.users)       as users,      -- 5
  (select count(*) from public.profiles)  as profiles,   -- 5
  (select count(*) from public.playlists) as playlists,  -- 30
  (select count(*) from public.demo_sessions) as demo_rows; -- 0

-- 7. Guard is a no-op for real traffic — functional checks outside SQL:
--    a) terminal, anon role through PostgREST + the hook:
--       curl -s -o NUL -w "%{http_code}" -H "apikey: sb_publishable_ZqEzyHbIGvHVCGvoSRU6kw_2QKU8dom" "https://jecgmiuypuathhvjuhea.supabase.co/rest/v1/genres?select=id&limit=1"
--       expect 200
--    b) mobile app with an existing account: open Home, Library, one playlist, like/unlike one track (write path)
--    c) one throwaway registration completes and can be deleted afterwards from Dashboard → Authentication
--    d) paax-api (still DEMO_ENABLED unset): POST https://api.paaxmusic.app/v2/demo/sessions → 503 DEMO_DISABLED
