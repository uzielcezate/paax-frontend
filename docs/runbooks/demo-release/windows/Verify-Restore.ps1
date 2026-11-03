# Verify-Restore.ps1 - LOCAL ONLY. Restores a Backup-Production.ps1 folder into an empty scratch database inside the
# isolated container `paax_verify_pg` and compares 06_backup_fingerprint.sql output with fp_production.txt.
# Production is never contacted. Prints RESULT: PASS or RESULT: FAIL with reasons.
#
#   powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Verify-Restore.ps1" [-BackupDir <folder>]
param(
  [string]$BackupDir  = "",
  [string]$BackupRoot = "C:\Users\uziel\PaaxBackups",
  [string]$RunbookDir = "",
  [string]$Container  = "paax_verify_pg",
  [string]$Image      = "public.ecr.aws/supabase/postgres:17.11.0.011",
  [switch]$KeepContainerRunning
)
$ErrorActionPreference = 'Stop'
if (-not $RunbookDir) { $RunbookDir = Split-Path -Parent $PSScriptRoot }
if (-not $BackupDir) {
  $BackupDir = (Get-ChildItem $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $BackupDir -or -not (Test-Path $BackupDir)) { throw "no backup folder found" }
Write-Host "backup folder : $BackupDir"
$fail = New-Object System.Collections.Generic.List[string]

# -- 0. files unchanged since the dump --
$sums = Get-Content (Join-Path $BackupDir 'SHA256SUMS.txt')
foreach ($line in $sums) {
  $h, $n = $line -split '\s+', 2
  $p = Join-Path $BackupDir $n
  if (-not (Test-Path $p)) { $fail.Add("missing file $n"); continue }
  if ((Get-FileHash $p -Algorithm SHA256).Hash -ne $h) { $fail.Add("checksum mismatch $n") }
}
foreach ($req in 'roles.sql', 'schema.sql', 'managed_schema.sql', 'data.sql', 'fp_production.txt') {
  if (-not (Test-Path (Join-Path $BackupDir $req))) { $fail.Add("required file missing: $req") }
}
$fpProd = Get-Content (Join-Path $BackupDir 'fp_production.txt')
if (-not $fpProd -or ($fpProd -join "`n") -match 'ERROR|FATAL') { $fail.Add("fp_production.txt is empty or contains an error") }
if (-not (Select-String -Path (Join-Path $BackupDir 'roles.sql') -Pattern 'authenticated' -Quiet)) { $fail.Add("roles.sql does not mention role authenticated") }
if (-not (Select-String -Path (Join-Path $BackupDir 'data.sql') -Pattern 'COPY "?auth"?\."?users"?' -Quiet)) { $fail.Add("data.sql has no COPY of auth.users") }
if ($fail.Count -gt 0) { $fail | ForEach-Object { Write-Host "FAIL: $_" }; Write-Host "RESULT: FAIL"; exit 1 }
Write-Host "checksums OK, required files present"

# -- 1. container --
$state = (docker ps -a --filter "name=^/$Container$" --format '{{.State}}' | Select-Object -First 1)
if (-not $state) {
  docker run -d --name $Container -e POSTGRES_PASSWORD=postgres -e POSTGRES_HOST_AUTH_METHOD=trust -p 127.0.0.1:54329:5432 --memory 768m $Image | Out-Null
} elseif ($state -ne 'running') { docker start $Container | Out-Null }
$ok = $false
for ($i = 0; $i -lt 40; $i++) { docker exec $Container pg_isready -U supabase_admin -d postgres 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $ok = $true; break }; Start-Sleep 2 }
if (-not $ok) { throw "container not ready" }

# -- 2. empty scratch database + platform fixtures (not application data) --
docker exec $Container psql -U supabase_admin -d postgres -q -c "drop database if exists paax_verify;" -c "create database paax_verify template template0;" | Out-Null
docker exec $Container sh -c "rm -rf /tmp/paax && mkdir -p /tmp/paax" | Out-Null
docker cp (Join-Path $PSScriptRoot 'scratch_db_fixtures.sql') "${Container}:/tmp/paax/fixtures.sql" | Out-Null
$fx = docker exec $Container sh -c "psql -U supabase_admin -d paax_verify -q -v ON_ERROR_STOP=1 -f /tmp/paax/fixtures.sql 2>&1" | ForEach-Object { "$_" }
if ($fx -match 'ERROR') { $fx | ForEach-Object { Write-Host $_ }; throw "scratch db fixtures failed" }

# -- 3. copy files in (byte-exact, no PowerShell re-encoding) and restore --
foreach ($f in 'managed_schema.sql', 'schema.sql', 'data.sql') { docker cp (Join-Path $BackupDir $f) "${Container}:/tmp/paax/$f" | Out-Null }
docker cp (Join-Path $RunbookDir '06_backup_fingerprint.sql') "${Container}:/tmp/paax/06.sql" | Out-Null

$harmless = @(
  'can only create extension in database postgres',
  'relation "supabase_functions.hooks" does not exist',
  'function private.handle_new_user\(\) does not exist',
  'function private.tg_on_auth_user_deleted\(\) does not exist'
)
foreach ($f in 'managed_schema.sql', 'schema.sql', 'data.sql') {
  Write-Host "== restoring $f"
  $errs = docker exec $Container sh -c "psql -U supabase_admin -d paax_verify -q -v ON_ERROR_STOP=0 -f /tmp/paax/$f 2>&1 | grep -E 'ERROR|FATAL' | sort | uniq -c"
  foreach ($e in ($errs | ForEach-Object { "$_" })) {
    if (-not $e.Trim()) { continue }
    $isHarmless = $false
    foreach ($h in $harmless) { if ($e -match $h) { $isHarmless = $true } }
    if ($isHarmless) { Write-Host "   (expected, harmless) $e" } else { Write-Host "   UNEXPECTED: $e"; $fail.Add("$f restore error: $e") }
  }
}

# -- 4. fingerprint on the restored db and compare --
$fpRest = docker exec $Container sh -c 'psql -U supabase_admin -d paax_verify -At -q -v ON_ERROR_STOP=1 -f /tmp/paax/06.sql 2>&1' | ForEach-Object { "$_" }
Set-Content -Path (Join-Path $BackupDir 'fp_restored.txt') -Value ($fpRest -join "`n") -Encoding utf8
$diff = Compare-Object -ReferenceObject $fpProd -DifferenceObject $fpRest
if ($diff) {
  Write-Host "== FINGERPRINTS DIFFER:"
  $diff | ForEach-Object { Write-Host ("   {0} {1}" -f $_.SideIndicator, $_.InputObject) }
  $fail.Add("fingerprint differs ($($diff.Count) lines)")
} else {
  Write-Host "== FINGERPRINTS IDENTICAL ($($fpProd.Count) lines: $(@($fpProd | Where-Object { $_ -notmatch 'NOTICE:' }).Count) md5 lines + $(@($fpProd | Where-Object { $_ -match 'NOTICE:' }).Count) exact table counts)"
}
Write-Host ""
Write-Host "== production fingerprint summary (restored is identical when PASS)"
$fpProd | Where-Object { $_ -notmatch 'NOTICE:' } | ForEach-Object { Write-Host "   $_" }
$fpProd | Where-Object { $_ -match 'NOTICE:' } | ForEach-Object { Write-Host ("   " + ($_ -replace '^NOTICE:\s*', '')) }

# -- 5. cleanup (local only) --
docker exec $Container psql -U supabase_admin -d postgres -q -c "drop database if exists paax_verify;" | Out-Null
docker exec $Container sh -c "rm -rf /tmp/paax" | Out-Null
if (-not $KeepContainerRunning) { docker stop $Container | Out-Null; Write-Host "container $Container stopped (kept for reuse; remove with: docker rm $Container)" }

Write-Host ""
if ($fail.Count -gt 0) { $fail | ForEach-Object { Write-Host "FAIL: $_" }; Write-Host "RESULT: FAIL"; exit 1 }
Write-Host "RESULT: PASS"
