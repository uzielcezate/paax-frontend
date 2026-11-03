#!/usr/bin/env bash
# STAGING ONLY — proves the backup procedure in 00_backup_free_plan.md is restorable, using the LOCAL stack as
# the "source" database. Dumps with the same five commands, restores into a scratch database, and compares
# 06_backup_fingerprint.sql output (counts + md5 over keys/emails/password hashes/tokens) between source and restore.
# Usage: bash docs/runbooks/demo-release/staging/run_backup_restore_test.sh <out_dir>
set -u
export MSYS_NO_PATHCONV=1
DB=supabase_db_web-demo-mode
RB=docs/runbooks/demo-release
OUT=${1:?out_dir}; mkdir -p "$OUT"
SRC_URL_CLI="postgresql://postgres:postgres@host.docker.internal:54322/postgres"   # seen from the CLI's dump container
echo "== 1. dump with the Supabase CLI (same flags as the production procedure)"
ok=1
npx supabase db dump --db-url "$SRC_URL_CLI" --role-only -f "$OUT/roles.sql"                                   || ok=0
npx supabase db dump --db-url "$SRC_URL_CLI" -f "$OUT/schema.sql"                                              || ok=0
npx supabase db dump --db-url "$SRC_URL_CLI" --schema auth,storage -f "$OUT/managed_schema.sql"                || ok=0
npx supabase db dump --db-url "$SRC_URL_CLI" --data-only --use-copy -f "$OUT/data.sql"                         || ok=0
npx supabase db dump --db-url "$SRC_URL_CLI" --data-only --use-copy --schema auth -f "$OUT/auth_data.sql"      || ok=0
npx supabase db dump --db-url "$SRC_URL_CLI" --data-only --use-copy --schema storage -f "$OUT/storage_data.sql" || ok=0
if [ "$ok" = 0 ]; then
  echo "!! CLI dump failed (see above); falling back to pg_dump inside the db container with equivalent flags"
  docker exec "$DB" pg_dumpall -U postgres --roles-only > "$OUT/roles.sql"
  docker exec "$DB" pg_dump -U postgres --schema-only --no-owner --no-privileges -n public -n private -n storage > "$OUT/schema.sql"
  docker exec "$DB" pg_dump -U postgres --data-only -n public -n private > "$OUT/data.sql"
  docker exec "$DB" pg_dump -U postgres --data-only -n auth > "$OUT/auth_data.sql"
  docker exec "$DB" pg_dump -U postgres --data-only -n storage > "$OUT/storage_data.sql"
fi
ls -la "$OUT"
echo "== 2. restore into an EMPTY scratch database paax_verify (template0 + the extensions the schema needs)"
docker exec "$DB" psql -U supabase_admin -d postgres -q -c "drop database if exists paax_verify;" -c "create database paax_verify template template0;"
# Supabase keeps extensions in schema `extensions` and realtime uses publication `supabase_realtime`; recreate both
# so the schema dump restores without errors (these are platform fixtures, not application data).
docker exec "$DB" psql -U supabase_admin -d paax_verify -q -c "create schema if not exists extensions; create schema if not exists supabase_functions; create schema if not exists private; create extension if not exists pgcrypto with schema extensions; create extension if not exists \"uuid-ossp\" with schema extensions; create extension if not exists pg_stat_statements with schema extensions; create extension if not exists supabase_vault cascade; create publication supabase_realtime;" 2>&1 | grep ERROR | head -3
docker exec -i "$DB" psql -U supabase_admin -d paax_verify -q -v ON_ERROR_STOP=0 -f - < "$OUT/managed_schema.sql" 2>&1 | grep -E "ERROR" | sort | uniq -c | head -8
docker exec -i "$DB" psql -U supabase_admin -d paax_verify -q -v ON_ERROR_STOP=0 -f - < "$OUT/schema.sql"    2>&1 | grep -E "ERROR" | sort | uniq -c | head -12
echo "(schema restore errors above, if any, are listed verbatim; expected: none)"
# data.sql (CLI --data-only without --schema) already contains auth, storage, public and private rows; the per-schema
# files are redundant safety copies. Restore data.sql once; restoring the extras too only produces duplicate-key errors.
docker exec -i "$DB" psql -U supabase_admin -d paax_verify -q -v ON_ERROR_STOP=0 -f - < "$OUT/data.sql"      2>&1 | grep -E "ERROR" | sort | uniq -c | head -8
echo "(auth_data.sql / storage_data.sql are subsets of data.sql — kept as redundant copies, not restored twice)"
echo "== 3. fingerprints (source vs restored) — must be identical"
docker exec -i "$DB" psql -U postgres -d postgres   -At -q -f - < "$RB/06_backup_fingerprint.sql" > "$OUT/fp_source.txt"   2>&1
docker exec -i "$DB" psql -U supabase_admin -d paax_verify -At -q -f - < "$RB/06_backup_fingerprint.sql" > "$OUT/fp_restored.txt" 2>&1
if diff "$OUT/fp_source.txt" "$OUT/fp_restored.txt" >/dev/null; then echo "FINGERPRINTS IDENTICAL"; else echo "FINGERPRINTS DIFFER:"; diff "$OUT/fp_source.txt" "$OUT/fp_restored.txt" | head -20; fi
head -14 "$OUT/fp_source.txt"
docker exec "$DB" psql -U supabase_admin -d postgres -q -c "drop database if exists paax_verify;"
echo "== done"
