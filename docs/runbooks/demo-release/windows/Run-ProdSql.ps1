# Run-ProdSql.ps1 - runs ONE runbook SQL file against the database named by the DPAPI secret, through psql inside the
# isolated container (URI over stdin only). Output is saved (URI scrubbed) under <BackupRoot>\release-log\ and printed.
#
#   -Kind apply      04_apply_option_a.sql   WRITES (one transaction, fail-closed). Requires -Confirm 'APPLY-DEMO-MIGRATION'.
#   -Kind postcheck  02_post_apply_checks.sql  read-only
#   -Kind cronruns   last 3 cron.job_run_details rows for paax_demo_cleanup   read-only
#   -Kind rollback   03_rollback_demo_guard.sql  WRITES (full rollback). Requires -Confirm 'ROLLBACK-DEMO'.
#   -Kind detach     05_emergency_detach_guard.sql  WRITES (hook off, seconds). Requires -Confirm 'DETACH-GUARD'.
#
#   powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Run-ProdSql.ps1" -Kind postcheck
param(
  [Parameter(Mandatory = $true)][ValidateSet('apply', 'postcheck', 'cronruns', 'rollback', 'detach')][string]$Kind,
  [string]$Confirm    = "",
  [string]$SecretFile = "C:\Users\uziel\PaaxSecrets\paax_db_url.dpapi",
  [string]$BackupRoot = "C:\Users\uziel\PaaxBackups",
  [string]$RunbookDir = "",
  [string]$Container  = "paax_verify_pg",
  [string]$Image      = "public.ecr.aws/supabase/postgres:17.11.0.011"
)
$ErrorActionPreference = 'Stop'
if (-not $RunbookDir) { $RunbookDir = Split-Path -Parent $PSScriptRoot }
$required = @{ apply = 'APPLY-DEMO-MIGRATION'; rollback = 'ROLLBACK-DEMO'; detach = 'DETACH-GUARD' }
if ($required.ContainsKey($Kind) -and $Confirm -ne $required[$Kind]) { throw "Kind '$Kind' writes to the target database; re-run with -Confirm '$($required[$Kind])' only after explicit authorization." }
$files = @{ apply = '04_apply_option_a.sql'; postcheck = '02_post_apply_checks.sql'; rollback = '03_rollback_demo_guard.sql'; detach = '05_emergency_detach_guard.sql' }

function Load-DbUrl {
  if (-not (Test-Path $SecretFile)) { throw "Secret file not found: $SecretFile" }
  $sec = Get-Content $SecretFile | ConvertTo-SecureString
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
function Scrub([string]$text, [string]$url) {
  if ($url -match '^(postgres(ql)?://[^:/@]+:)([^@]+)@') { $pw = $Matches[3]; return $text.Replace($url, '<db-url>').Replace($pw, '***') }
  return $text.Replace($url, '<db-url>')
}
$url    = Load-DbUrl
$masked = $url -replace '^(postgres(ql)?://[^:/@]+:)[^@]+@', '$1***@'
$logDir = Join-Path $BackupRoot 'release-log'
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp  = Get-Date -Format 'yyyy-MM-dd_HHmmss'
Write-Host "target : $masked"
Write-Host "kind   : $Kind"

$state = (docker ps -a --filter "name=^/$Container$" --format '{{.State}}' | Select-Object -First 1)
if (-not $state) { docker run -d --name $Container -e POSTGRES_PASSWORD=postgres -e POSTGRES_HOST_AUTH_METHOD=trust -p 127.0.0.1:54329:5432 --memory 768m $Image | Out-Null }
elseif ($state -ne 'running') { docker start $Container | Out-Null }
$ok = $false
for ($i = 0; $i -lt 40; $i++) { docker exec $Container pg_isready -U supabase_admin -d postgres 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $ok = $true; break }; Start-Sleep 2 }
if (-not $ok) { throw "container not ready" }
docker exec $Container sh -c "rm -rf /tmp/paax && mkdir -p /tmp/paax/out" | Out-Null
docker cp (Join-Path $PSScriptRoot 'container_dump.sh') "${Container}:/tmp/paax/dump.sh" | Out-Null
docker exec $Container sh -c "sed -i 's/\r$//' /tmp/paax/dump.sh" | Out-Null
if ($files.ContainsKey($Kind)) {
  $num = $files[$Kind].Substring(0, 2)
  docker cp (Join-Path $RunbookDir $files[$Kind]) "${Container}:/tmp/paax/$num.sql" | Out-Null
  docker exec $Container sh -c "sed -i 's/\r$//' /tmp/paax/$num.sql" | Out-Null
}

$ErrorActionPreference = 'Continue'
$res  = $url | docker exec -i $Container sh /tmp/paax/dump.sh $Kind 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$outFile = "${Kind}_output.txt"
$body = docker exec $Container sh -c "cat /tmp/paax/out/$outFile 2>/dev/null" | ForEach-Object { "$_" }
docker exec $Container sh -c "rm -rf /tmp/paax" | Out-Null
$text = Scrub ((@($res | ForEach-Object { "$_" }) + @('--- output ---') + @($body)) -join "`n") $url
$url  = $null
$log  = Join-Path $logDir "${stamp}_$Kind.txt"
Set-Content -Path $log -Value $text -Encoding utf8
Write-Host $text
Write-Host ""
Write-Host "psql exit : $code   (apply: 0 = committed; anything else = nothing committed)"
Write-Host "log       : $log"
if ($code -ne 0) { exit $code }
