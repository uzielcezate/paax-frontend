# Backup before the demo migration — Supabase Free plan

Free projects have no PITR and no downloadable Dashboard backups, so the backup is a **logical dump you make
yourself** with the Supabase CLI (it runs `pg_dump` in Docker, so Docker Desktop must be running). Everything is
written to a private folder on your machine; nothing is pasted into chat or committed.

> **Windows 11 (automated):** `windows/README.md` wraps sections 1–2 (plus the preflight and the fingerprint) in
> three PowerShell scripts — `Save-PaaxDbUrl.ps1` (DPAPI-encrypted credential, run by you), `Backup-Production.ps1`
> (read-only dumps + fingerprint + preflight) and `Verify-Restore.ps1` (restore proof in one isolated container,
> PASS/FAIL). Dry-run verified 2026-11-03. The manual commands below remain the reference.

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

This exact set of commands was exercised end to end against the local stack on 2026-11-03
(`staging/run_backup_restore_test.sh`): dump → restore into an empty database → fingerprint comparison identical.

```powershell
# roles (names/memberships/grants; Supabase never exports role passwords)
npx supabase db dump --db-url $env:PAAX_DB_URL --role-only -f roles.sql
# application schemas: public + private (tables, functions, triggers, RLS policies, grants)
npx supabase db dump --db-url $env:PAAX_DB_URL -f schema.sql
# managed schemas' DDL: auth + storage (needed to rebuild an empty database)
npx supabase db dump --db-url $env:PAAX_DB_URL --schema auth,storage -f managed_schema.sql
# ALL data in COPY format — includes auth (users, identities, sessions, refresh tokens), storage metadata, public, private
npx supabase db dump --db-url $env:PAAX_DB_URL --data-only --use-copy -f data.sql
# redundant per-schema copies of the sensitive data (subsets of data.sql; restore data.sql once, keep these as spares)
npx supabase db dump --db-url $env:PAAX_DB_URL --data-only --use-copy --schema auth -f auth_data.sql
npx supabase db dump --db-url $env:PAAX_DB_URL --data-only --use-copy --schema storage -f storage_data.sql
```

Then run `06_backup_fingerprint.sql` in the production SQL editor (read-only) and save its full output as
`fp_production.txt` next to the dumps. `Get-ChildItem | Select Name, Length` and keep the listing with the files.

## 2. Verify the backup is restorable (local only, production untouched)

Restore into an **empty** scratch database inside the local Supabase stack (same Postgres 17 major, same Supabase
roles) and compare fingerprints. The exact fingerprint lines (count + md5 over ids / emails / password hashes /
refresh tokens / object names) and the exact per-table counts must be identical to `fp_production.txt`; matching
counts alone are not accepted.

```powershell
# from the worktree root (where supabase/config.toml lives)
npx supabase start
$db = "supabase_db_web-demo-mode"
docker exec $db psql -U supabase_admin -d postgres -q -c "drop database if exists paax_verify;" -c "create database paax_verify template template0;"
# platform fixtures the dumps reference (not application data)
docker exec $db psql -U supabase_admin -d paax_verify -q -c "create schema if not exists extensions; create schema if not exists supabase_functions; create schema if not exists private; create extension if not exists pgcrypto with schema extensions; create extension if not exists ""uuid-ossp"" with schema extensions; create extension if not exists pg_stat_statements with schema extensions; create extension if not exists supabase_vault cascade; create publication supabase_realtime;"
Get-Content managed_schema.sql | docker exec -i $db psql -U supabase_admin -d paax_verify -q
Get-Content schema.sql         | docker exec -i $db psql -U supabase_admin -d paax_verify -q
Get-Content data.sql           | docker exec -i $db psql -U supabase_admin -d paax_verify -q
Get-Content ..\..\<repo>\docs\runbooks\demo-release\06_backup_fingerprint.sql | docker exec -i $db psql -U supabase_admin -d paax_verify -At -q > fp_restored.txt 2>&1
Compare-Object (Get-Content fp_production.txt) (Get-Content fp_restored.txt)   # expect NO output
```

Expected, harmless messages during the schema restore (seen in staging): `can only create extension in database
postgres` (pg_cron line, scratch db only), `relation "supabase_functions.hooks" does not exist` (platform
table), and `function private.handle_new_user() / private.tg_on_auth_user_deleted() does not exist` (two
`auth.users` triggers in `managed_schema.sql` reference functions that `schema.sql` creates afterwards; they only
matter for new signups in the scratch db, not for verifying data — for a real rebuild, run `managed_schema.sql` a
second time after `schema.sql` so those two triggers are created). Anything else, or any difference in the fingerprint comparison, means the backup is not trustworthy:
stop and report before applying anything. Afterwards
`docker exec $db psql -U supabase_admin -d postgres -c "drop database paax_verify;"` and `npx supabase stop`.

## 3. Restore procedure (only if a rollback ever needs data, which this migration does not)

The migration adds objects and a role setting; `03_rollback_demo_guard.sql` undoes it without touching data.
A data restore would only be needed for an unrelated disaster. Procedure: run `03_rollback_demo_guard.sql`,
then restore the affected tables from `data.sql` (it already contains the auth and storage rows) after truncating
them — do this only with a second explicit review, never as part of this release.

## 4. Privacy

`roles.sql`, `data.sql` and `auth_data.sql` contain personal data (emails, hashed passwords, refresh tokens).
Keep the folder local and private, do not upload it, and delete it once the release is confirmed stable.
`$env:PAAX_DB_URL` disappears when the shell closes; do not add it to any `.env` file in the repo.
