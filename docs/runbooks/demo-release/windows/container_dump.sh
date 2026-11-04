#!/bin/sh
# Runs INSIDE the isolated container paax_verify_pg. Reads the connection URI from the FIRST LINE OF STDIN (never an
# argument, never an env var set from the host), then performs ONE read-only operation against that database and
# writes the result under /tmp/paax/out. Usage: sh /tmp/paax/dump.sh <kind>   (URI piped on stdin)
#   preflight       psql 01_migration_audit.sql (echoed)           -> preflight_production.txt
#   fingerprint     psql 06_backup_fingerprint.sql (unaligned)     -> fp_production.txt
#   roles           pg_dumpall --roles-only --no-role-passwords     -> roles.sql
#   schema          pg_dump --schema-only  -n public -n private     -> schema.sql
#   managed_schema  pg_dump --schema-only  -n auth   -n storage     -> managed_schema.sql
#   data            pg_dump --data-only    public+private+auth+storage (COPY) -> data.sql
#   auth_data       pg_dump --data-only    -n auth                  -> auth_data.sql   (spare copy)
#   storage_data    pg_dump --data-only    -n storage               -> storage_data.sql (spare copy)
set -u
IFS= read -r U || exit 90
U=$(printf '%s' "$U" | tr -d '\r\n')   # PowerShell pipes CRLF line endings
U=${U#"$(printf '\357\273\277')"}      # ...and a UTF-8 BOM in front of native stdin (PowerShell 5.1)
[ -n "$U" ] || exit 91
mkdir -p /tmp/paax/out
export PGCONNECT_TIMEOUT=20
case "${1:-}" in
  preflight)      psql "$U" --echo-queries -v ON_ERROR_STOP=0 -f /tmp/paax/01.sql > /tmp/paax/out/preflight_production.txt 2>&1 ;;
  fingerprint)    psql "$U" -At -q -v ON_ERROR_STOP=1 -f /tmp/paax/06.sql > /tmp/paax/out/fp_production.txt 2>&1 ;;
  roles)          pg_dumpall -d "$U" --roles-only --no-role-passwords > /tmp/paax/out/roles.sql 2> /tmp/paax/out/err.txt ;;
  schema)         pg_dump "$U" --schema-only -n public -n private > /tmp/paax/out/schema.sql 2> /tmp/paax/out/err.txt ;;
  managed_schema) pg_dump "$U" --schema-only -n auth -n storage > /tmp/paax/out/managed_schema.sql 2> /tmp/paax/out/err.txt ;;
  data)           pg_dump "$U" --data-only -n public -n private -n auth -n storage > /tmp/paax/out/data.sql 2> /tmp/paax/out/err.txt ;;
  auth_data)      pg_dump "$U" --data-only -n auth > /tmp/paax/out/auth_data.sql 2> /tmp/paax/out/err.txt ;;
  storage_data)   pg_dump "$U" --data-only -n storage > /tmp/paax/out/storage_data.sql 2> /tmp/paax/out/err.txt ;;
  # ---- release-stage operations (WRITE to the target; only via Apply-Migration.ps1 / Run-ProdSql.ps1) ----
  apply)          psql "$U" --echo-errors -v ON_ERROR_STOP=1 -f /tmp/paax/04.sql > /tmp/paax/out/apply_output.txt 2>&1 ;;        # file holds begin;...commit; any error -> psql exits, connection closes, transaction rolls back
  postcheck)      psql "$U" --echo-queries -v ON_ERROR_STOP=0 -f /tmp/paax/02.sql > /tmp/paax/out/postcheck_output.txt 2>&1 ;;
  rollback)       psql "$U" --echo-queries -v ON_ERROR_STOP=0 -f /tmp/paax/03.sql > /tmp/paax/out/rollback_output.txt 2>&1 ;;
  detach)         psql "$U" --echo-queries -v ON_ERROR_STOP=0 -f /tmp/paax/05.sql > /tmp/paax/out/detach_output.txt 2>&1 ;;
  cronruns)       psql "$U" -At -c "select status, return_message, start_time from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'paax_demo_cleanup') order by start_time desc limit 3;" > /tmp/paax/out/cronruns_output.txt 2>&1 ;;
  *) echo "unknown kind: ${1:-}" >&2; exit 92 ;;
esac
rc=$?
unset U
# never echo the URI: stderr of the dump tools is saved to err.txt (scrubbed on the host) and only its size is printed
[ -s /tmp/paax/out/err.txt ] && echo "stderr bytes: $(wc -c < /tmp/paax/out/err.txt)"
exit $rc
