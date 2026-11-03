-- Option A apply script: the committed migration file verbatim, wrapped in ONE transaction.
-- Generated from supabase/migrations/20261030000000_demo_sessions.sql; do not edit by hand.
begin;
-- ============================================================================
-- Demo sessions — secure, server-enforced 10-minute portfolio demo (2026-10-30)
--
-- A demo visitor is a REAL, isolated auth.users row created by paax-api
-- (service role) with `app_metadata.paax_demo = true`, a random password that
-- is never stored, and a `demo_sessions` row carrying the authoritative
-- expiry. Isolation comes for free from the existing RLS (every private table
-- is keyed by auth.uid()).
--
-- Server-side enforcement (the client timer is cosmetic):
--   1. `public.paax_pre_request()` is installed as the PostgREST pre-request
--      hook. For JWTs carrying `app_metadata.paax_demo = true` it rejects every
--      request once the session is expired/ended (HTTP 401, hint
--      DEMO_SESSION_EXPIRED) and blocks the social-mutation RPCs (HTTP 403).
--      Non-demo JWTs return immediately — the hook is a no-op for real users.
--   2. `private.demo_cleanup()` deletes expired demo users (cascades wipe their
--      profile, library, playlists, notifications). Scheduled with pg_cron
--      every minute when the extension is available; paax-api also sweeps on
--      every session creation as a backstop.
--
-- Rollback:
--   alter role authenticator reset pgrst.db_pre_request; notify pgrst, 'reload config';
--   select cron.unschedule('paax_demo_cleanup');
--   drop function if exists private.demo_cleanup(), public.paax_pre_request(),
--     public.demo_session_status();
--   drop table if exists public.demo_sessions;
-- ============================================================================

create table if not exists public.demo_sessions (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  started_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  ended_at    timestamptz,
  client      text,
  constraint demo_sessions_expiry_after_start check (expires_at > started_at)
);

comment on table public.demo_sessions is
  'Authoritative lifetime of a portfolio demo identity. One row per demo auth user.';

create index if not exists idx_demo_sessions_expires_at
  on public.demo_sessions (expires_at);

alter table public.demo_sessions enable row level security;

-- A demo user may read ONLY its own row (to show remaining time). Nobody can
-- write through PostgREST as anon/authenticated; paax-api writes with the
-- service role.
drop policy if exists "Demo users read their own session" on public.demo_sessions;
create policy "Demo users read their own session"
  on public.demo_sessions for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.demo_sessions from anon, authenticated;
grant select on public.demo_sessions to authenticated;

-- ── Status RPC (client convenience; the pre-request hook is the gate) ────────
create or replace function public.demo_session_status()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'active',            d.ended_at is null and d.expires_at > now(),
        'started_at',        d.started_at,
        'expires_at',        d.expires_at,
        'ended_at',          d.ended_at,
        'remaining_seconds', greatest(0, floor(extract(epoch from (d.expires_at - now())))::int),
        'server_time',       now()
      )
      from public.demo_sessions d
      where d.user_id = (select auth.uid())
    ),
    jsonb_build_object('active', false, 'remaining_seconds', 0, 'server_time', now())
  );
$$;

revoke execute on function public.demo_session_status() from public, anon;
grant execute on function public.demo_session_status() to authenticated, service_role;

-- ── PostgREST pre-request hook ───────────────────────────────────────────────
-- Runs inside every PostgREST transaction before the main query. MUST be cheap
-- and MUST NOT raise for non-demo callers: every branch that is not the
-- intentional demo rejection is wrapped so an unexpected error can never take
-- the API down for real users.
create or replace function public.paax_pre_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims  jsonb;
  v_uid     uuid;
  v_expires timestamptz;
  v_ended   timestamptz;
  v_path    text;
  v_method  text;
begin
  begin
    v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  exception when others then
    return;
  end;

  if v_claims is null
     or coalesce(v_claims->>'role', '') <> 'authenticated'
     or coalesce(v_claims->'app_metadata'->>'paax_demo', '') <> 'true' then
    return; -- not a demo identity: no-op
  end if;

  begin
    v_uid := (v_claims->>'sub')::uuid;
  exception when others then
    return;
  end;

  select d.expires_at, d.ended_at into v_expires, v_ended
  from public.demo_sessions d
  where d.user_id = v_uid;

  if not found or v_ended is not null or v_expires <= now() then
    raise sqlstate 'PT401' using
      message = 'demo_session_expired',
      detail  = 'This demo session has ended. Start a new demo to continue.',
      hint    = 'DEMO_SESSION_EXPIRED';
  end if;

  -- Social mutations are disabled for demo identities: they must not be able
  -- to invite, befriend or hand playlists to real users.
  v_path   := coalesce(current_setting('request.path', true), '');
  v_method := upper(coalesce(current_setting('request.method', true), ''));

  if v_path like '/rpc/playlist_invite_collaborator%'
     or v_path = '/rpc/search_invitable_profiles'
     or v_path = '/rpc/playlist_transfer_ownership'
     or (v_path like '/user_friendships%' and v_method <> 'GET')
     or (v_path like '/user_blocks%' and v_method <> 'GET') then
    raise sqlstate 'PT403' using
      message = 'demo_action_not_allowed',
      detail  = 'Inviting, befriending or transferring to other users is disabled in the demo.',
      hint    = 'DEMO_ACTION_NOT_ALLOWED';
  end if;
end;
$$;

-- PostgREST calls the hook as the request role, so each API role needs EXECUTE.
grant execute on function public.paax_pre_request() to anon, authenticated, service_role;

alter role authenticator set pgrst.db_pre_request = 'public.paax_pre_request';
notify pgrst, 'reload config';

-- ── Cleanup of expired demo identities ───────────────────────────────────────
create or replace function private.demo_cleanup(p_grace_seconds int default 60, p_limit int default 100)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  with doomed as (
    select d.user_id
    from public.demo_sessions d
    where d.expires_at < now() - make_interval(secs => p_grace_seconds)
       or d.ended_at is not null
    order by d.expires_at
    limit p_limit
  ),
  deleted as (
    delete from auth.users u
    using doomed
    where u.id = doomed.user_id
      and coalesce(u.raw_app_meta_data->>'paax_demo', '') = 'true' -- never touch a real user
    returning u.id
  )
  select count(*) into v_count from deleted;
  return v_count;
end;
$$;

revoke execute on function private.demo_cleanup(int, int) from public, anon, authenticated;

-- pg_cron is optional: schedule the sweep when the extension can be enabled.
do $$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'pg_cron not available (%): demo cleanup relies on the paax-api sweep', sqlerrm;
    return;
  end;
  perform cron.unschedule(jobid) from cron.job where jobname = 'paax_demo_cleanup';
  perform cron.schedule('paax_demo_cleanup', '* * * * *', 'select private.demo_cleanup();');
end;
$$;

commit;
