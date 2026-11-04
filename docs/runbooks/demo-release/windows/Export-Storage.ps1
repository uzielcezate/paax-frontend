# Export-Storage.ps1 - READ-ONLY export of Supabase Storage object CONTENTS listed in a backup folder.
#
# The PostgreSQL backup holds only storage METADATA (storage.objects rows). This script downloads every object those
# rows describe into <backup>\storage\<bucket>\<path> (paths preserved verbatim) and verifies each file against the
# row's metadata: size == metadata.size and MD5 == eTag (Supabase/S3 single-part uploads use the MD5 as eTag).
# Public buckets are fetched through the public endpoint without any credential. Objects in private buckets are
# listed as SKIPPED_PRIVATE (none exist today); exporting them would need a key and a separate approval.
# Nothing is written to Supabase: GET requests only; bucket policies and paths are untouched.
#
#   powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Export-Storage.ps1" [-BackupDir <folder>]
param(
  [string]$BackupDir   = "",
  [string]$BackupRoot  = "C:\Users\uziel\PaaxBackups",
  [string]$ProjectUrl  = "https://jecgmiuypuathhvjuhea.supabase.co"
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not $BackupDir) { $BackupDir = (Get-ChildItem $BackupRoot -Directory | Where-Object { $_.Name -match '-pre-demo$' } | Sort-Object Name -Descending | Select-Object -First 1).FullName }
if (-not (Test-Path (Join-Path $BackupDir 'storage_data.sql'))) { throw "storage_data.sql not found in $BackupDir" }
Write-Host "backup folder : $BackupDir"

function Read-CopyRows([string[]]$lines, [string]$table) {
  $start = ($lines | Select-String -Pattern ('^COPY "?storage"?\."?' + $table + '"? ') | Select-Object -First 1).LineNumber
  if (-not $start) { return @() }
  $rows = New-Object System.Collections.Generic.List[string[]]
  for ($k = $start; $k -lt $lines.Count; $k++) {
    if ($lines[$k] -eq '\.') { break }
    $rows.Add(($lines[$k] -split "`t"))
  }
  return $rows
}
function Unescape-Copy([string]$s) { return $s.Replace('\\', [string][char]1).Replace('\t', "`t").Replace('\n', "`n").Replace([string][char]1, '\') }

$lines   = Get-Content (Join-Path $BackupDir 'storage_data.sql')
$buckets = @{}
foreach ($b in (Read-CopyRows $lines 'buckets')) { $buckets[$b[0]] = ($b[5] -eq 't') }   # id, name, owner, created, updated, public
$objects = Read-CopyRows $lines 'objects'                                              # id, bucket_id, name, owner, created, updated, last_accessed, metadata, ...
Write-Host ("buckets       : " + (($buckets.GetEnumerator() | ForEach-Object { "{0}(public={1})" -f $_.Key, $_.Value }) -join ', '))
Write-Host "objects       : $($objects.Count)"

$outRoot  = Join-Path $BackupDir 'storage'
$manifest = New-Object System.Collections.Generic.List[object]
$n = 0
foreach ($o in $objects) {
  $n++
  $bucket = $o[1]; $name = $o[2]
  $meta   = (Unescape-Copy $o[7]) | ConvertFrom-Json
  $etag   = ([string]$meta.eTag).Trim('"')
  $size   = [long]$meta.size
  $rec    = [ordered]@{ bucket = $bucket; name = $name; size = $size; etag = $etag; status = ''; local_size = ''; local_md5 = '' }
  if (-not $buckets.ContainsKey($bucket) -or -not $buckets[$bucket]) { $rec.status = 'SKIPPED_PRIVATE'; $manifest.Add([pscustomobject]$rec); continue }
  $dest = Join-Path $outRoot (Join-Path $bucket ($name -replace '/', '\'))
  New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
  $path = (($name -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $url  = "$ProjectUrl/storage/v1/object/public/$bucket/$path"
  try {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 60 | Out-Null
    $lsize = (Get-Item $dest).Length
    $lmd5  = (Get-FileHash $dest -Algorithm MD5).Hash.ToLower()
    $rec.local_size = $lsize; $rec.local_md5 = $lmd5
    if ($lsize -eq $size -and ($etag -match '-' -or $lmd5 -eq $etag)) { $rec.status = if ($etag -match '-') { 'OK_SIZE_ONLY_MULTIPART' } else { 'OK' } }
    else { $rec.status = 'MISMATCH' }
  } catch {
    $rec.status = 'DOWNLOAD_FAILED: ' + $_.Exception.Message
  }
  $manifest.Add([pscustomobject]$rec)
  if ($n % 25 -eq 0) { Write-Host "  $n / $($objects.Count)" }
}
$manifest | Export-Csv -Path (Join-Path $BackupDir 'storage_manifest.csv') -NoTypeInformation -Encoding UTF8
$summary = $manifest | Group-Object status | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }
Write-Host ""
Write-Host "== storage export summary"
$summary | ForEach-Object { Write-Host "  $_" }
$bytes = ($manifest | Where-Object { $_.status -like 'OK*' } | Measure-Object -Property size -Sum).Sum
Write-Host ("  bytes verified: {0}" -f $bytes)
$bad = @($manifest | Where-Object { $_.status -notlike 'OK*' -and $_.status -ne 'SKIPPED_PRIVATE' })
if ($bad.Count -gt 0) { $bad | ForEach-Object { Write-Host "FAIL: $($_.bucket)/$($_.name) $($_.status)" }; Write-Host "RESULT: FAIL"; exit 1 }
Write-Host "RESULT: PASS"
