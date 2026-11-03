# Backup-Production.ps1 - READ-ONLY against production. Windows 11 / PowerShell 5.1 / Docker Desktop.
#
# 1. loads the Session pooler URI saved by Save-PaaxDbUrl.ps1 (DPAPI; never printed, scrubbed from logs)
# 2. starts (or reuses) ONE isolated Supabase Postgres container `paax_verify_pg` (used only for its psql here)
# 3. runs 01_migration_audit.sql (sections A–F, all SELECT/SHOW) against production  -> preflight_production.txt
# 4. runs 06_backup_fingerprint.sql against production                                -> fp_production.txt
# 5. takes the six Supabase-CLI dumps of 00_backup_free_plan.md §1                   -> roles.sql, schema.sql, ...
# 6. writes SHA256SUMS.txt and FILES.txt
# Everything lands in a new folder under $BackupRoot (outside the repo and outside OneDrive).
# Nothing is written to production: pg_dump and SELECT/SHOW only. No migration, no extension, no role change.
#
#   powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Backup-Production.ps1"
param(
  [string]$SecretFile = "C:\Users\uziel\PaaxSecrets\paax_db_url.dpapi",
  [string]$BackupRoot = "C:\Users\uziel\PaaxBackups",
  [string]$RunbookDir = "",
  [string]$Container  = "paax_verify_pg",
  [string]$Image      = "public.ecr.aws/supabase/postgres:17.11.0.011"
)
$ErrorActionPreference = 'Stop'
if (-not $RunbookDir) { $RunbookDir = Split-Path -Parent $PSScriptRoot }
if ($BackupRoot -like "*\OneDrive\*") { throw "BackupRoot must not be inside OneDrive." }

function Load-DbUrl {
  if (-not (Test-Path $SecretFile)) { throw "Secret file not found: $SecretFile - run windows\Save-PaaxDbUrl.ps1 in your own PowerShell window first." }
  $sec  = Get-Content $SecretFile | ConvertTo-SecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
function Scrub([string]$text, [string]$url) {
  if ($url -match '^(postgres(ql)?://[^:/@]+:)([^@]+)@') { $pw = $Matches[3]; return $text.Replace($url, '<db-url>').Replace($pw, '***') }
  return $text.Replace($url, '<db-url>')
}
function Ensure-Container {
  $state = (docker ps -a --filter "name=^/$Container$" --format '{{.State}}' | Select-Object -First 1)
  if (-not $state) {
    Write-Host "starting isolated container $Container ($Image)"
    docker run -d --name $Container -e POSTGRES_PASSWORD=postgres -e POSTGRES_HOST_AUTH_METHOD=trust -p 127.0.0.1:54329:5432 --memory 768m $Image | Out-Null
  } elseif ($state -ne 'running') {
    docker start $Container | Out-Null
  }
  $ok = $false
  for ($i = 0; $i -lt 40; $i++) {
    $r = docker exec $Container pg_isready -U supabase_admin -d postgres 2>$null
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Start-Sleep -Seconds 2
  }
  if (-not $ok) { throw "container $Container did not become ready" }
}

$url    = Load-DbUrl
$masked = $url -replace '^(postgres(ql)?://[^:/@]+:)[^@]+@', '$1***@'
$stamp  = Get-Date -Format 'yyyy-MM-dd_HHmm'
$out    = Join-Path $BackupRoot "$stamp-pre-demo"
New-Item -ItemType Directory -Path $out -Force | Out-Null
icacls $BackupRoot /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
Write-Host "backup folder : $out"
Write-Host "target        : $masked"

Ensure-Container
docker exec $Container sh -c "mkdir -p /tmp/paax" | Out-Null
docker cp (Join-Path $RunbookDir '01_migration_audit.sql')    "${Container}:/tmp/paax/01.sql" | Out-Null
docker cp (Join-Path $RunbookDir '06_backup_fingerprint.sql') "${Container}:/tmp/paax/06.sql" | Out-Null

# -- read-only queries against production (psql runs inside the container; URL passed as env, not argv of psql) --
Write-Host "== preflight 01_migration_audit.sql (read-only)"
$pre = docker exec -e "PAAX_DB_URL=$url" $Container sh -c 'psql "$PAAX_DB_URL" --echo-queries -v ON_ERROR_STOP=0 -f /tmp/paax/01.sql 2>&1'
$preText = Scrub (($pre | ForEach-Object { "$_" }) -join "`n") $url
Set-Content -Path (Join-Path $out 'preflight_production.txt') -Value $preText -Encoding utf8
if ($preText -match 'could not connect|password authentication failed|Tenant or user not found|SSL') { Write-Host $preText; throw "preflight could not run against production (see above)" }

Write-Host "== fingerprint 06_backup_fingerprint.sql on production (read-only)"
$fp = docker exec -e "PAAX_DB_URL=$url" $Container sh -c 'psql "$PAAX_DB_URL" -At -q -v ON_ERROR_STOP=1 -f /tmp/paax/06.sql 2>&1'
$fpText = Scrub (($fp | ForEach-Object { "$_" }) -join "`n") $url
Set-Content -Path (Join-Path $out 'fp_production.txt') -Value $fpText -Encoding utf8
if ($fpText -match 'ERROR|FATAL') { Write-Host $fpText; throw "fingerprint failed on production" }

# -- dumps (Supabase CLI runs pg_dump in Docker; read-only) --
$dumps = @(
  @{ f = 'roles.sql';          a = @('--role-only') },
  @{ f = 'schema.sql';         a = @() },
  @{ f = 'managed_schema.sql'; a = @('--schema', 'auth,storage') },
  @{ f = 'data.sql';           a = @('--data-only', '--use-copy') },
  @{ f = 'auth_data.sql';      a = @('--data-only', '--use-copy', '--schema', 'auth') },
  @{ f = 'storage_data.sql';   a = @('--data-only', '--use-copy', '--schema', 'storage') }
)
$log = Join-Path $out 'dump_log.txt'
Set-Content -Path $log -Value "supabase db dump log $stamp (URL scrubbed)" -Encoding utf8
Push-Location $out
try {
  foreach ($d in $dumps) {
    Write-Host ("== dump {0} {1}" -f $d.f, ($d.a -join ' '))
    $args = @('supabase', 'db', 'dump', '--db-url', $url) + $d.a + @('-f', $d.f)
    $ErrorActionPreference = 'Continue'   # PS 5.1 turns native stderr (e.g. the CLI's deprecation warning) into errors under 'Stop'
    $res  = & npx @args 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $txt  = Scrub (($res | ForEach-Object { "$_" }) -join "`n") $url
    Add-Content -Path $log -Value ("--- {0} (exit {1})`n{2}" -f $d.f, $code, $txt) -Encoding utf8
    if ($code -ne 0 -or -not (Test-Path $d.f) -or (Get-Item $d.f).Length -lt 100) { Write-Host $txt; throw ("dump {0} failed (exit {1})" -f $d.f, $code) }
  }
} finally { Pop-Location }

# -- manifest --
$files = Get-ChildItem $out -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' -and $_.Name -ne 'FILES.txt' }
$files | ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.Name } | Set-Content (Join-Path $out 'SHA256SUMS.txt') -Encoding ascii
$files | ForEach-Object { "{0,12}  {1}" -f $_.Length, $_.Name } | Set-Content (Join-Path $out 'FILES.txt') -Encoding ascii
$url = $null

Write-Host ""
Write-Host "== files"
Get-Content (Join-Path $out 'FILES.txt')
Write-Host ""
Write-Host "== fingerprint (production) - table lines"
Get-Content (Join-Path $out 'fp_production.txt') | Where-Object { $_ -notmatch 'NOTICE:' } | Select-Object -First 14
Write-Host ""
Write-Host "== preflight (production) - full output follows"
Get-Content (Join-Path $out 'preflight_production.txt')
Write-Host ""
Write-Host "BACKUP_DIR=$out"
