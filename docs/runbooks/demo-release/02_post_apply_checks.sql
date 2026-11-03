-- PAAX demo migration POST-APPLY checks (READ-ONLY). All four must pass before DEMO_ENABLED=true.

-- 1. Hook attached to the API role and visible to PostgREST after `notify pgrst, 'reload config'`
select rolconfig from pg_roles where rolname = 'authenticator';
-- expect: {... pgrst.db_pre_request=public.paax_pre_request ...}

-- 2. Sweeper scheduled
select jobname, schedule, active from cron.job where jobname = 'paax_demo_cleanup';
-- expect: paax_demo_cleanup | * * * * * | t

-- 3. Objects present, RLS on, no demo rows yet
select relname, relrowsecurity from pg_class where relname = 'demo_sessions';
select count(*) as demo_rows from public.demo_sessions;

-- 4. The guard is a no-op for a real user (run as service role; emulates a non-demo JWT):
--    PostgREST evaluation happens per request, so the real check is functional:
--    open the mobile app with an existing account -> Home, Library and a playlist must load,
--    and a fresh registration must complete. Also run from a terminal:
--      curl -s -H "apikey: <publishable>" "https://jecgmiuypuathhvjuhea.supabase.co/rest/v1/genres?select=id&limit=1"
--    expect 200 (anon role passes through the hook).
