# Save-PaaxDbUrl.ps1 - store the Supabase SESSION POOLER connection URI privately on this Windows machine.
#
# RUN THIS YOURSELF in your own PowerShell window (Windows Terminal / PowerShell, not through Claude Code and not
# with the "!" prefix), so the password never enters a chat, a log, PSReadLine history or a source file:
#
#   powershell -ExecutionPolicy Bypass -File "<repo>\docs\runbooks\demo-release\windows\Save-PaaxDbUrl.ps1"
#
# Where to copy the URI: Supabase Dashboard -> project -> "Connect" (top bar) -> Session pooler -> URI. It looks like
#   postgresql://postgres.jecgmiuypuathhvjuhea:[YOUR-PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres
# Replace [YOUR-PASSWORD] with the database password (Project Settings -> Database -> "Reset database password" if
# unknown; the app does not use it, it uses API keys). The URI is read as a SecureString (nothing is echoed) and
# written encrypted with Windows DPAPI, decryptable only by this Windows user account on this machine.
# The file lives OUTSIDE the repository and OUTSIDE OneDrive. Delete it after the release: Remove-Item -Recurse $SecretDir
param(
  [string]$SecretDir = "C:\Users\uziel\PaaxSecrets"
)
$ErrorActionPreference = 'Stop'

if ($SecretDir -like "*\OneDrive\*") { throw "SecretDir must not be inside OneDrive." }
if (-not (Test-Path $SecretDir)) { New-Item -ItemType Directory -Path $SecretDir | Out-Null }
# restrict the folder to the current user only (no inheritance)
icacls $SecretDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null

Write-Host ""
Write-Host "Paste the Session pooler URI and press Enter. Nothing is echoed while you paste." -ForegroundColor Cyan
$sec = Read-Host -AsSecureString "Session pooler URI"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

if ($plain -match '\[YOUR-PASSWORD\]|\[PASSWORD\]') { throw "The URI still contains the [PASSWORD] placeholder. Nothing saved." }
if ($plain -notmatch '^postgres(ql)?://[^:/@]+:[^@]+@[^/@\s]+/[^\s]+$') { throw "That does not look like postgresql://user:password@host:port/db. Nothing saved." }
if ($plain -notmatch 'pooler\.supabase\.com:5432/') { Write-Warning "This is not the Session pooler (port 5432 on *.pooler.supabase.com). Direct/transaction-pooler URIs may fail on Free (IPv6) or with pg_dump. Saved anyway." }

$target = Join-Path $SecretDir 'paax_db_url.dpapi'
$sec | ConvertFrom-SecureString | Set-Content -Path $target -Encoding ascii
$masked = $plain -replace '^(postgres(ql)?://[^:/@]+:)[^@]+@', '$1***@'
$plain = $null
Write-Host ""
Write-Host "Saved (DPAPI, this Windows user only): $target" -ForegroundColor Green
Write-Host "Stored as: $masked"
Write-Host "You can now tell Claude Code the secret is saved; the backup scripts read it in-process and never print it."
