-- PAAX production PREFLIGHT for the demo migration (READ-ONLY). Supabase SQL editor, project jecgmiuypuathhvjuhea.
-- Sections A–B were already run on 2026-11-02 (results in AUDIT_2026-11-02.md). Sections C–F are the dependency
-- checks requested before applying; every query is a SELECT/SHOW and changes nothing.

-- ── A. Recorded migration history ──────────────────────────────────────────────────────────────────────
select version, name, inserted_at from supabase_migrations.schema_migrations order by version;

-- ── B. Demo objects must be ABSENT ────────────────────────────────────────────────────────────────────
select
  to_regclass('public.demo_sessions')                                   as demo_sessions_table,  -- expect null
  (select count(*) from pg_proc where proname = 'paax_pre_request')     as pre_request_fn,       -- expect 0
  (select count(*) from pg_proc where proname = 'demo_cleanup')         as cleanup_fn,           -- expect 0
  (select count(*) from pg_proc where proname = 'demo_session_status')  as status_fn;            -- expect 0

-- ── C. Schema dependencies the migration and paax-api rely on ─────────────────────────────────────────
-- C1. schema private (created by migration extensions_and_helpers)
select nspname from pg_namespace where nspname = 'private';                                   -- expect 1 row
-- C2. auth.users columns used by the guard and the sweeper
select column_name, data_type from information_schema.columns
 where table_schema = 'auth' and table_name = 'users'
   and column_name in ('id', 'raw_app_meta_data', 'email');                                   -- expect 3 rows, raw_app_meta_data = jsonb
-- C3. profiles columns paax-api writes when it completes a demo profile
select column_name, data_type, is_nullable from information_schema.columns
 where table_schema = 'public' and table_name = 'profiles'
   and column_name in ('id', 'username', 'display_name', 'country_code', 'onboarding_completed'); -- expect 5 rows
-- C4. profile auto-creation trigger on auth.users (paax-api UPDATEs the row the trigger creates, INSERTs only as fallback)
select tgname from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;      -- expect the on-signup profile trigger
-- C5. every private table is keyed by auth.uid() → RLS must be enabled on the tables a demo user can reach
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
 order by 1;                                                                                 -- expect only public catalog tables (artists, albums, tracks, genres, ...); no user-data table
-- C6. the social RPCs the guard blocks by path (informational; absence is harmless)
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and proname in ('playlist_invite_collaborator', 'search_invitable_profiles', 'playlist_transfer_ownership');
select to_regclass('public.user_friendships') as user_friendships, to_regclass('public.user_blocks') as user_blocks;

-- ── D. PostgREST pre-request hook: nothing configured today ───────────────────────────────────────────
select rolname, rolconfig from pg_roles where rolname in ('authenticator', 'anon', 'authenticated', 'service_role');
--   expect 4 rows; authenticator.rolconfig must NOT contain pgrst.db_pre_request
select coalesce(current_setting('pgrst.db_pre_request', true), '(none)') as current_pre_request;  -- expect (none)

-- ── E. pg_cron readiness (Option A) ──────────────────────────────────────────────────────────────────
select name, default_version, installed_version from pg_available_extensions where name = 'pg_cron';  -- expect 1 row, installed_version null
show shared_preload_libraries;                                                                      -- expect list containing pg_cron
select current_database();                                                                          -- expect postgres (pg_cron runs jobs in this db)
select nspname from pg_namespace where nspname = 'cron';                                            -- expect 0 rows today
select rolname, rolsuper, rolcreaterole from pg_roles where rolname = current_user;                 -- expect postgres

-- ── F. Baseline to compare after apply / after any rollback ──────────────────────────────────────────
select
  (select count(*) from auth.users)        as users,       -- 5 on 2026-11-02
  (select count(*) from public.profiles)   as profiles,    -- 5
  (select count(*) from public.playlists)  as playlists,   -- 30
  (select count(*) from auth.users where coalesce(raw_app_meta_data->>'paax_demo','') = 'true') as demo_users; -- 0
