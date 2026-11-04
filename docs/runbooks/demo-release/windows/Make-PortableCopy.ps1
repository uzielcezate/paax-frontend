# Make-PortableCopy.ps1 - turn the DPAPI-protected backup into a PASSPHRASE-protected portable copy and prove it.
#
# RUN THIS YOURSELF in your own PowerShell window (not through Claude Code, not with "!"), because it asks for the
# recovery passphrase. The passphrase is read as a SecureString (not echoed, not in PSReadLine history), used only
# in-process, never written anywhere. Nothing contacts Supabase; the DPAPI copy is left intact.
#
#   powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Make-PortableCopy.ps1"
#
# What it does:
#  1. decrypts <name>.paaxbak (DPAPI key, this account) to a temporary zip and checks its SHA256 against the value
#     recorded in <name>.paaxbak.sha256 (= the inner zip of the verified backup)
#  2. asks for the recovery passphrase twice (min 16 chars; warns if it looks weak) and encrypts the SAME zip to
#     <name>.portable.paaxbak (PBKDF2-SHA256 300k -> AES-256-CBC + HMAC-SHA256)
#  3. INDEPENDENCE PROOF: decrypts the portable copy with the passphrase only, with the DPAPI key directory pointed
#     at a non-existent folder, and compares SHA256 with the original inner zip
#  4. deletes the temporary zips; prints the SHA256 of the portable file for the offline copies
param(
  [string]$BackupRoot = "C:\Users\uziel\PaaxBackups",
  [string]$SecretDir  = "C:\Users\uziel\PaaxSecrets",
  [string]$DpapiFile  = ""
)
$ErrorActionPreference = 'Stop'
if (-not $DpapiFile) { $DpapiFile = (Get-ChildItem $BackupRoot -File -Filter '*-pre-demo.paaxbak' | Sort-Object Name -Descending | Select-Object -First 1).FullName }
if (-not $DpapiFile -or -not (Test-Path $DpapiFile)) { throw "no *-pre-demo.paaxbak found in $BackupRoot" }
$base     = $DpapiFile -replace '\.paaxbak$', ''
$portable = "$base.portable.paaxbak"
if (Test-Path $portable) { throw "$portable already exists; refusing to overwrite" }
$recorded = (Get-Content "$DpapiFile.sha256" | Select-Object -First 1) -split '\s+' | Select-Object -First 1
Write-Host "DPAPI copy    : $DpapiFile"
Write-Host "recorded zip  : sha256 $recorded"

# -- 1. decrypt the DPAPI copy (this account) --
$tmpZip = "$base.portable-src.zip"
& (Join-Path $PSScriptRoot 'Unprotect-Backup.ps1') -EncryptedFile $DpapiFile -OutFile $tmpZip -SecretDir $SecretDir | Out-Null
$srcHash = (Get-FileHash $tmpZip -Algorithm SHA256).Hash
if ($srcHash -ne $recorded) { Remove-Item $tmpZip -Force; throw "decrypted zip sha256 $srcHash differs from the recorded $recorded" }
Write-Host "step 1        : DPAPI copy decrypted, sha256 matches the verified backup -> OK"

# -- 2. passphrase --
Write-Host ""
Write-Host "Choose a strong, unique recovery passphrase (e.g. 6+ random words, or 20+ mixed characters)." -ForegroundColor Cyan
Write-Host "It is the ONLY way to open the portable copy. Nothing is echoed." -ForegroundColor Cyan
try {
  $sec  = Read-Host -AsSecureString "Recovery passphrase"
  $sec2 = Read-Host -AsSecureString "Repeat passphrase"
} catch { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue; throw }
$b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec);  $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
$b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2); $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
if ($p1 -ne $p2) { Remove-Item $tmpZip -Force; throw "passphrases differ; nothing created" }
if ($p1.Length -lt 16) { Remove-Item $tmpZip -Force; throw "passphrase shorter than 16 characters; nothing created" }
$classes = @(($p1 -cmatch '[a-z]'), ($p1 -cmatch '[A-Z]'), ($p1 -match '\d'), ($p1 -match '[^A-Za-z0-9]'), ($p1 -match '\s')) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
$words = ($p1 -split '\s+' | Where-Object { $_ }).Count
if ($p1.Length -lt 20 -and $classes -lt 3 -and $words -lt 5) { Write-Warning "Passphrase looks weak (short, few character classes, few words). Consider Ctrl+C and choosing a longer one." }
$p1 = $null; $p2 = $null
$sec2.Dispose()

# -- 3. encrypt the same zip with the passphrase (round-trip proof inside Protect-Backup.ps1) --
& (Join-Path $PSScriptRoot 'Protect-Backup.ps1') -KeyMode passphrase -InputZip $tmpZip -OutFile $portable -PassphraseSecure $sec
if (-not (Test-Path $portable)) { throw "portable copy was not created" }

# -- 4. independence proof: passphrase only, DPAPI key directory unreachable --
$tmpRt = "$base.portable-check.zip"
& (Join-Path $PSScriptRoot 'Unprotect-Backup.ps1') -EncryptedFile $portable -OutFile $tmpRt -SecretDir 'C:\__no_such_dir__' -PassphraseSecure $sec | Out-Null
$sec.Dispose()
$rtHash = (Get-FileHash $tmpRt -Algorithm SHA256).Hash
Remove-Item $tmpRt, $tmpZip -Force
if ($rtHash -ne $recorded) { Remove-Item $portable -Force; throw "portable copy decrypted to a different sha256; discarded" }
$outer = (Get-FileHash $portable -Algorithm SHA256).Hash
Write-Host ""
Write-Host "step 4        : portable copy decrypted with the passphrase ONLY (DPAPI dir = non-existent), sha256 matches -> OK"
Write-Host "portable file : $portable"
Write-Host ("portable size : {0} bytes" -f (Get-Item $portable).Length)
Write-Host "portable sha256: $outer   (also in $portable.sha256; compare after copying to offline media)"
Write-Host "RESULT: PASS"
