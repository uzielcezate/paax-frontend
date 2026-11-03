# Backup before the demo migration — Supabase Free plan

Free projects have no PITR and no downloadable Dashboard backups, so the backup is a **logical dump you make
yourself** with the Supabase CLI (it runs `pg_dump` in Docker, so Docker Desktop must be running). Everything is
written to a private folder on your machine; nothing is pasted into chat or committed.

## 0. Prerequisites (you)

- Docker Desktop running; `npx supabase --version` works (used throughout this project).
- Dashboard → Project Settings → Database → **Connection string → Session pooler** (IPv4-friendly on Free),
  URI form. It looks like `postgresql://postgres.jecgmiuypuathhvjuhea:[PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres`.
  If you do not know the database password, reset it there first (this does not affect the app: the app uses API
  keys, not the DB password).
- Put the URI in an environment variable **in your own shell only** (never in a file in the repo):
  - PowerShell: `$env:PAAX_DB_URL = "postgresql://postgres.jecgmiuypuathhvjuhea:...@aws-0-....pooler.supabase.com:5432/postgres"`
- Create a private folder outside the repo, e.g. `C:\Users\uziel\PaaxBackups\2026-11-xx-pre-demo\` and `cd` into it.

## 1. Take the dumps (read-only against production; ~35 MB database, a minute or two)

```powershell
# roles (passwords are not exported by Supabase's dump; role names/grants are)
npx supabase db dump --db-url $env:PAAX_DB_URL --role-only -f roles.sql
# schema of every app schema (public, private, storage policies, functions, triggers, RLS, grants)
npx supabase db dump --db-url $env:PAAX_DB_URL -f schema.sql
# data of the app schemas (COPY format, restorable with psql)
npx supabase db dump --db-url $env:PAAX_DB_URL --data-only --use-copy -f data.sql
# authentication data: users, identities, sessions, refresh tokens (auth schema is excluded by default)
npx supabase db dump --db-url $env:PAAX_DB_URL --data-only --use-copy --schema auth -f auth_data.sql
# storage object metadata (files themselves live in object storage and are not touched by the migration)
npx supabase db dump --db-url $env:PAAX_DB_URL --data-only --use-copy --schema storage -f storage_data.sql
```

Record the baseline next to the dumps (also in `01_migration_audit.sql` §5): `auth.users` 5, `public.profiles` 5,
`public.playlists` 30. Then: `Get-ChildItem | Select Name, Length` and keep the listing with the files.

## 2. Verify the backup is restorable (local only, production untouched)

Restore into a scratch database inside the local Supabase stack (it has the same Postgres 17 major and the
Supabase roles, so the dumps apply cleanly):

```powershell
# from the worktree root (where supabase/config.toml lives)
npx supabase start
docker exec supabase_db_web-demo-mode psql -U postgres -c "drop database if exists paax_verify;" -c "create database paax_verify;"
Get-Content schema.sql    | docker exec -i supabase_db_web-demo-mode psql -U postgres -d paax_verify -v ON_ERROR_STOP=1 -q
Get-Content auth_data.sql | docker exec -i supabase_db_web-demo-mode psql -U postgres -d paax_verify -v ON_ERROR_STOP=1 -q
Get-Content data.sql      | docker exec -i supabase_db_web-demo-mode psql -U postgres -d paax_verify -v ON_ERROR_STOP=1 -q
docker exec supabase_db_web-demo-mode psql -U postgres -d paax_verify -At -c "select (select count(*) from auth.users), (select count(*) from public.profiles), (select count(*) from public.playlists);"
```

Expected output: `5|5|30`. If any step stops with an error, the backup is not trustworthy: stop and report before
applying anything. Afterwards `docker exec supabase_db_web-demo-mode psql -U postgres -c "drop database paax_verify;"`
and `npx supabase stop`.

Note: the `auth` schema in the scratch database comes from the local stack's own auth migrations (GoTrue
version may be slightly newer); if `auth_data.sql` reports an unknown column, that is a local/remote GoTrue
version skew, not a broken dump. In that case verify the dump by content instead:
`Select-String -Path auth_data.sql -Pattern "COPY auth.users" -Context 0,6`.

## 3. Restore procedure (only if a rollback ever needs data, which this migration does not)

The migration adds objects and a role setting; `03_rollback_demo_guard.sql` undoes it without touching data.
A data restore would only be needed for an unrelated disaster. Procedure: run `03_rollback_demo_guard.sql`,
then restore with `psql $env:PAAX_DB_URL -v ON_ERROR_STOP=1 -f data.sql` (and `auth_data.sql`) after truncating
the affected tables — do this only with a second explicit review, never as part of this release.

## 4. Privacy

`roles.sql`, `data.sql` and `auth_data.sql` contain personal data (emails, hashed passwords, refresh tokens).
Keep the folder local and private, do not upload it, and delete it once the release is confirmed stable.
`$env:PAAX_DB_URL` disappears when the shell closes; do not add it to any `.env` file in the repo.
