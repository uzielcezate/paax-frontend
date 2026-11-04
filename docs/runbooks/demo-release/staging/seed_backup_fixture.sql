-- STAGING ONLY. Gives the local stack some auth + user data so the backup/restore test has something to prove:
-- two real-looking users (with identities, a session and a refresh token) and two playlists.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('33333333-3333-4333-8333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'backup-fixture-a@example.com', '$2a$10$fixturehashA', now(), '{"provider":"email","providers":["email"]}', '{"username":"fixture_a"}', now(), now()),
  ('44444444-4444-4444-8444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'backup-fixture-b@example.com', '$2a$10$fixturehashB', now(), '{"provider":"email","providers":["email"]}', '{"username":"fixture_b"}', now(), now())
on conflict (id) do nothing;

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values
  ('33333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-333333333333', '33333333-3333-4333-8333-333333333333', 'email', '{"sub":"33333333-3333-4333-8333-333333333333","email":"backup-fixture-a@example.com"}', now(), now(), now()),
  ('44444444-4444-4444-8444-444444444444', '44444444-4444-4444-8444-444444444444', '44444444-4444-4444-8444-444444444444', 'email', '{"sub":"44444444-4444-4444-8444-444444444444","email":"backup-fixture-b@example.com"}', now(), now(), now())
on conflict (id) do nothing;

insert into auth.sessions (id, user_id, created_at, updated_at, aal)
values ('55555555-5555-4555-8555-555555555555', '33333333-3333-4333-8333-333333333333', now(), now(), 'aal1')
on conflict (id) do nothing;

insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at, session_id)
values ('00000000-0000-0000-0000-000000000000', 'fixture-refresh-token-a', '33333333-3333-4333-8333-333333333333', false, now(), now(), '55555555-5555-4555-8555-555555555555')
on conflict do nothing;

-- profiles rows are created by the signup trigger; playlists reference them
insert into public.playlists (id, owner_id, name, visibility)
values
  ('66666666-6666-4666-8666-666666666666', '33333333-3333-4333-8333-333333333333', 'fixture playlist A', 'private'),
  ('77777777-7777-4777-8777-777777777777', '44444444-4444-4444-8444-444444444444', 'fixture playlist B', 'public')
on conflict (id) do nothing;

select (select count(*) from auth.users) users, (select count(*) from public.profiles) profiles, (select count(*) from public.playlists) playlists;
