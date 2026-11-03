# Windows 11 procedure: production preflight + backup + restore proof (read-only on production)

Automates `00_backup_free_plan.md` §1-2 and `01_migration_audit.sql` on Windows with PowerShell 5.1, Docker Desktop
and the Supabase CLI (`npx supabase`, v3). Production is only ever read (SELECT/SHOW and `pg_dump`). No migration,
extension, role, history or configuration change happens here. Dry-run verified on 2026-11-03 against a local
stand-in database (same scripts, same container image): six dumps, fingerprint identical, `RESULT: PASS`.

## Memory footprint

Instead of the full local Supabase stack, one container `paax_verify_pg` (image
`public.ecr.aws/supabase/postgres:17.11.0.011`, capped at 768 MB, port 127.0.0.1:54329) provides psql for the
read-only production queries and the scratch database for the restore proof. It is stopped after the restore and can
be removed with `docker rm paax_verify_pg`.

## 1. Credentials, privately (you, once)

In your own PowerShell window (not in chat, not with the `!` prefix):

```powershell
powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Save-PaaxDbUrl.ps1"
```

Paste the **Session pooler** URI from Dashboard -> Connect -> Session pooler (`postgresql://postgres.<ref>:PASSWORD@aws-0-<region>.pooler.supabase.com:5432/postgres`).
The input is a SecureString (not echoed, not stored in PSReadLine history) and is written DPAPI-encrypted to
`C:\Users\uziel\PaaxSecrets\paax_db_url.dpapi` (current Windows user only, folder ACL restricted, outside OneDrive
and outside the repo). Nothing else ever prints it: the scripts decrypt it in-process, pass it to psql through the
container environment and to the CLI as an argument, and scrub it from every saved log. Delete the folder after the release.

Why the session pooler: Free projects are IPv6-only on the direct host; the session pooler is IPv4, speaks plain
Postgres protocol and supports `pg_dump` (the transaction pooler on port 6543 does not).

## 2. Preflight + backup (read-only on production)

```powershell
powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Backup-Production.ps1"
```

Writes `C:\Users\uziel\PaaxBackups\<date>-pre-demo\` (ACL restricted to you, outside OneDrive):

| file | content |
|---|---|
| `preflight_production.txt` | `01_migration_audit.sql` sections A-F with the queries echoed |
| `fp_production.txt` | `06_backup_fingerprint.sql`: 13 `table|count|md5` lines + `COUNT schema.table=N` for every table in public/private/auth/storage |
| `roles.sql` | role names/memberships/settings (Supabase never exports role passwords) |
| `schema.sql` | public + private DDL (tables, functions, triggers, RLS policies, grants) |
| `managed_schema.sql` | auth + storage DDL |
| `data.sql` | ALL rows (auth users/identities/sessions/refresh tokens, storage metadata, public, private), COPY format |
| `auth_data.sql`, `storage_data.sql` | spare per-schema copies (subsets of `data.sql`) |
| `dump_log.txt`, `SHA256SUMS.txt`, `FILES.txt` | CLI output (URL scrubbed), checksums, sizes |

The script aborts on any connection failure, any `ERROR` in the fingerprint, any non-zero dump exit or a dump under 100 bytes.

## 3. Restore proof (local only)

```powershell
powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Verify-Restore.ps1"
```

Takes the newest backup folder: verifies SHA256 of every file, requires `roles.sql` to name `authenticated` and
`data.sql` to carry `COPY auth.users`, creates an empty `paax_verify` database (`template0` + `scratch_db_fixtures.sql`),
restores `managed_schema.sql` -> `schema.sql` -> `data.sql` (files are copied into the container byte-exact; no
PowerShell re-encoding), runs `06_backup_fingerprint.sql` on the restored database and compares it line by line with
`fp_production.txt`. Prints `RESULT: PASS` or `RESULT: FAIL` with every reason, drops the scratch database and
stops the container.

Expected, harmless restore messages (whitelisted): the two `auth.users` triggers in `managed_schema.sql` referencing
`private.handle_new_user()` / `private.tg_on_auth_user_deleted()` before `schema.sql` creates them, the
`supabase_functions.hooks` platform table, and `can only create extension in database postgres`. Anything else is a FAIL.

## 4. PASS/FAIL criteria for authorizing `04_apply_option_a.sql`

All of the following, otherwise do not apply:

Preflight (`preflight_production.txt`):
- B: `demo_sessions_table` null, `pre_request_fn` 0, `cleanup_fn` 0, `status_fn` 0.
- C1 one row `private`; C2 three rows with `raw_app_meta_data` = `jsonb`; C3 five `profiles` columns; C4 a trigger on
  `auth.users`; C5 lists only catalog/plan tables (no profiles/playlists/liked/followed/demo tables); C6 informational.
- D: `authenticator.rolconfig` contains no `pgrst.db_pre_request`; `current_pre_request` = `(none)`.
- E: `pg_cron` row with `installed_version` empty; `shared_preload_libraries` contains `pg_cron`; `current_database` =
  `postgres`; no `cron` schema; current role `postgres` with `rolsuper` f.
- F: users 5, profiles 5, playlists 30, demo_users 0 (any drift from the 2026-11-02 baseline must be explained first).

Backup:
- Six dump files, every exit 0, `data.sql` contains `COPY auth.users`, `roles.sql` non-trivial.
- `Verify-Restore.ps1` printed `RESULT: PASS` (fingerprints identical: all md5 lines including `auth.users`
  password hashes / app metadata, identities, sessions, refresh tokens, plus every exact table count).

Blockers (do not apply): any connection or dump error; any fingerprint difference; any unexpected restore error;
`pg_cron` missing from `shared_preload_libraries` or already installed; a pre-request hook already configured;
demo objects already present; baseline counts unexplained; `rolsuper` t (unexpected role).
