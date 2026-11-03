-- STAGING ONLY (local Supabase stack). Seeds one expired demo identity and one REAL-looking user with an
-- expired-looking demo_sessions row but WITHOUT the paax_demo flag, to prove the sweeper deletes only the
-- former. Never run against production.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'demo-staging-expired@demo.paaxmusic.app', 'x', now(),
   '{"provider":"email","providers":["email"],"paax_demo":true}', '{"username":"demo_staging1"}', now(), now()),
  ('22222222-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'real-staging-user@example.com', 'x', now(),
   '{"provider":"email","providers":["email"]}', '{"username":"real_staging1"}', now(), now())
on conflict (id) do nothing;

-- Both rows look expired to the sweeper's time test; only the first carries the demo flag.
insert into public.demo_sessions (user_id, started_at, expires_at, client)
values
  ('11111111-1111-4111-8111-111111111111', now() - interval '20 minutes', now() - interval '10 minutes', 'staging'),
  ('22222222-2222-4222-8222-222222222222', now() - interval '20 minutes', now() - interval '10 minutes', 'staging')
on conflict (user_id) do nothing;

select id, email, raw_app_meta_data->>'paax_demo' as paax_demo from auth.users
 where id in ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222') order by id;
