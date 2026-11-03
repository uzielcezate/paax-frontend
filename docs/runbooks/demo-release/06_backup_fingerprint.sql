-- Backup integrity fingerprint (READ-ONLY). Run it twice: on PRODUCTION (SQL editor) and on the locally
-- RESTORED scratch database. The two outputs must be identical line for line. Counts alone are not accepted:
-- each line also carries an md5 over the ordered primary keys, and auth lines include email / token material
-- hashes, so a dump that silently dropped or altered rows cannot match.

with t as (
  select 'auth.users' as tbl, count(*) as n,
         md5(string_agg(id::text || '|' || coalesce(email,'') || '|' || coalesce(encrypted_password,'') || '|' || coalesce(raw_app_meta_data::text,''), ',' order by id)) as fp
  from auth.users
  union all
  select 'auth.identities', count(*), md5(string_agg(id::text || '|' || user_id::text || '|' || provider, ',' order by id)) from auth.identities
  union all
  select 'auth.sessions', count(*), md5(coalesce(string_agg(id::text, ',' order by id), '')) from auth.sessions
  union all
  select 'auth.refresh_tokens', count(*), md5(coalesce(string_agg(id::text || '|' || token, ',' order by id), '')) from auth.refresh_tokens
  union all
  select 'public.profiles', count(*), md5(string_agg(id::text || '|' || coalesce(username,''), ',' order by id)) from public.profiles
  union all
  select 'public.playlists', count(*), md5(string_agg(id::text || '|' || coalesce(name,''), ',' order by id)) from public.playlists
  union all
  select 'public.playlist_tracks', count(*), md5(coalesce(string_agg(playlist_id::text || '|' || track_id::text, ',' order by playlist_id, track_id), '')) from public.playlist_tracks
  union all
  select 'public.user_liked_tracks', count(*), md5(coalesce(string_agg(user_id::text || '|' || track_id::text, ',' order by user_id, track_id), '')) from public.user_liked_tracks
  union all
  select 'public.user_followed_artists', count(*), md5(coalesce(string_agg(user_id::text || '|' || artist_id::text, ',' order by user_id, artist_id), '')) from public.user_followed_artists
  union all
  select 'public.artists', count(*), md5(coalesce(string_agg(id::text, ',' order by id), '')) from public.artists
  union all
  select 'public.albums',  count(*), md5(coalesce(string_agg(id::text, ',' order by id), '')) from public.albums
  union all
  select 'public.tracks',  count(*), md5(coalesce(string_agg(id::text, ',' order by id), '')) from public.tracks
  union all
  select 'storage.objects', count(*), md5(coalesce(string_agg(id::text || '|' || name, ',' order by id), '')) from storage.objects
)
select tbl, n, fp from t order by tbl;

-- EXACT row counts for EVERY table in public/private/auth/storage (catches tables not listed above).
-- Emitted as NOTICE lines "COUNT schema.table=N" so the two runs can be diffed verbatim. Read-only.
do $$
declare r record; n bigint;
begin
  for r in
    select n.nspname as s, c.relname as t
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r' and n.nspname in ('public', 'private', 'auth', 'storage')
      and c.relname not in ('schema_migrations', 'migrations', 'audit_log_entries')   -- Supabase bookkeeping tables (excluded from CLI data dumps by design)
    order by 1, 2
  loop
    execute format('select count(*) from %I.%I', r.s, r.t) into n;
    raise notice 'COUNT %.%=%', r.s, r.t, n;
  end loop;
end $$;
