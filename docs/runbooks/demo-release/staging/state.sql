-- Compact state line for staging runs (local only). Safe whether or not pg_cron is installed.
do $$
declare
  v_jobs text := 'pg_cron-absent';
  v_hook text;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select coalesce(string_agg(jobname || ':' || active::text, ','), 'no-jobs') from cron.job$q$ into v_jobs;
  end if;
  select case when exists (select 1 from pg_roles where rolname = 'authenticator'
                             and array_to_string(rolconfig, ',') like '%pgrst.db_pre_request=public.paax_pre_request%')
              then 'hook-on' else 'hook-off' end into v_hook;
  raise notice 'STATE demo_table=% fns=% pg_cron_ext=% jobs=% hook=% users=%',
    coalesce(to_regclass('public.demo_sessions')::text, 'absent'),
    (select count(*) from pg_proc where proname in ('paax_pre_request', 'demo_cleanup', 'demo_session_status')),
    (select count(*) from pg_extension where extname = 'pg_cron'),
    v_jobs, v_hook, (select count(*) from auth.users);
end $$;
