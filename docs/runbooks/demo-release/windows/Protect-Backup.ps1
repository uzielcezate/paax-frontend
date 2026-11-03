# Protect-Backup.ps1 - encrypt a backup folder at rest (Windows 11 Home: no EFS, BitLocker not manageable), using
# only built-in .NET: AES-256-CBC + HMAC-SHA256 (encrypt-then-MAC), key either
#   -KeyMode dpapi       (default) a random 64-byte master key stored DPAPI-protected for THIS Windows user in
#                        <SecretDir>\backup_key.dpapi (created once; non-interactive). Readable only by this account
#                        on this machine - export/keep a passphrase copy if the backup must survive a reinstall.
#   -KeyMode passphrase  key derived with PBKDF2-SHA256 (300k iterations, random salt) from a passphrase you type
#                        (SecureString prompt; portable, survives account/machine loss).
# Steps: zip the folder -> encrypt to <folder>.paaxbak -> decrypt the result back to a temp file and compare SHA256
# with the zip (round-trip proof) -> only then delete the zip and (with -RemovePlaintext) the plaintext folder.
# Reverse with Unprotect-Backup.ps1. File layout: "PAAXBAK1" | mode(1) | salt(16) | iv(16) | ciphertext | hmac(32).
#
#   powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Protect-Backup.ps1" [-BackupDir <folder>] [-RemovePlaintext]
param(
  [string]$BackupDir  = "",
  [string]$BackupRoot = "C:\Users\uziel\PaaxBackups",
  [string]$SecretDir  = "C:\Users\uziel\PaaxSecrets",
  [ValidateSet('dpapi', 'passphrase')][string]$KeyMode = 'dpapi',
  [switch]$RemovePlaintext
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
if (-not $BackupDir) { $BackupDir = (Get-ChildItem $BackupRoot -Directory | Where-Object { $_.Name -match '-pre-demo$' } | Sort-Object Name -Descending | Select-Object -First 1).FullName }
if (-not (Test-Path $BackupDir)) { throw "backup folder not found" }
$BackupDir = $BackupDir.TrimEnd('\')
$zip = "$BackupDir.zip"; $enc = "$BackupDir.paaxbak"
if (Test-Path $enc) { throw "$enc already exists; refusing to overwrite" }
Write-Host "backup folder : $BackupDir"

# -- key material (64 bytes: 32 AES + 32 HMAC) --
$rng  = [Security.Cryptography.RandomNumberGenerator]::Create()
$salt = New-Object byte[] 16; $rng.GetBytes($salt)
$iv   = New-Object byte[] 16; $rng.GetBytes($iv)
if ($KeyMode -eq 'dpapi') {
  $keyFile = Join-Path $SecretDir 'backup_key.dpapi'
  if (-not (Test-Path $keyFile)) {
    if (-not (Test-Path $SecretDir)) { New-Item -ItemType Directory -Path $SecretDir | Out-Null }
    & icacls $SecretDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $SecretDir" }
    $master = New-Object byte[] 64; $rng.GetBytes($master)
    $blob = [Security.Cryptography.ProtectedData]::Protect($master, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($keyFile, $blob)
    Write-Host "created DPAPI-protected master key: $keyFile (this Windows user only)"
  }
  $master = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyFile), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  $modeByte = 1
} else {
  $sec  = Read-Host -AsSecureString "Backup passphrase (min 12 chars)"
  $sec2 = Read-Host -AsSecureString "Repeat passphrase"
  $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec); $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
  $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2); $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
  if ($p1 -ne $p2) { throw "passphrases differ" }
  if ($p1.Length -lt 12) { throw "passphrase too short" }
  $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($p1, $salt, 300000, [Security.Cryptography.HashAlgorithmName]::SHA256)
  $master = $kdf.GetBytes(64); $p1 = $null; $p2 = $null
  $modeByte = 2
}
$aesKey = $master[0..31]; $macKey = $master[32..63]

# -- 1. zip --
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$BackupDir\*" -DestinationPath $zip -CompressionLevel Optimal
$zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash
Write-Host ("zip           : {0} bytes, sha256 {1}" -f (Get-Item $zip).Length, $zipHash)

# -- 2. encrypt (AES-256-CBC) + HMAC-SHA256 over header+ciphertext --
$aes = [Security.Cryptography.Aes]::Create(); $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $aesKey; $aes.IV = $iv
$magic = [Text.Encoding]::ASCII.GetBytes('PAAXBAK1')
$hmac  = New-Object Security.Cryptography.HMACSHA256(,$macKey)
# ciphertext first to a temp file through CryptoStream (correct CBC/PKCS7 handling), then header|ct|hmac
$ctTmp = "$enc.ct"
$fsCt  = [IO.File]::Create($ctTmp)
$cs    = New-Object Security.Cryptography.CryptoStream($fsCt, $aes.CreateEncryptor(), [Security.Cryptography.CryptoStreamMode]::Write)
$fsIn  = [IO.File]::OpenRead($zip)
try { $fsIn.CopyTo($cs); $cs.FlushFinalBlock() } finally { $fsIn.Close(); $cs.Close(); $fsCt.Close() }
$fsOut = [IO.File]::Create($enc)
try {
  $header = $magic + [byte[]]@($modeByte) + $salt + $iv
  $fsOut.Write($header, 0, $header.Length)
  $hmac.TransformBlock($header, 0, $header.Length, $null, 0) | Out-Null
  $fsCt = [IO.File]::OpenRead($ctTmp)
  $buf  = New-Object byte[] 1048576
  while (($read = $fsCt.Read($buf, 0, $buf.Length)) -gt 0) { $fsOut.Write($buf, 0, $read); $hmac.TransformBlock($buf, 0, $read, $null, 0) | Out-Null }
  $fsCt.Close()
  $hmac.TransformFinalBlock(@(), 0, 0) | Out-Null
  $fsOut.Write($hmac.Hash, 0, 32)
} finally { $fsOut.Close(); Remove-Item $ctTmp -Force -ErrorAction SilentlyContinue }
Write-Host ("encrypted     : {0} ({1} bytes)" -f $enc, (Get-Item $enc).Length)

# -- 3. round-trip proof: decrypt with Unprotect-Backup.ps1 logic to a temp file and compare SHA256 --
$tmp = "$zip.roundtrip"
& (Join-Path $PSScriptRoot 'Unprotect-Backup.ps1') -EncryptedFile $enc -OutFile $tmp -SecretDir $SecretDir -MasterKeyBytes $master | Out-Null
$rtHash = (Get-FileHash $tmp -Algorithm SHA256).Hash
Remove-Item $tmp -Force
if ($rtHash -ne $zipHash) { Remove-Item $enc -Force; throw "round-trip SHA256 mismatch; encrypted file discarded, plaintext kept" }
Write-Host "round-trip    : decrypt(encrypt(zip)) sha256 matches -> OK"
"{0}  {1}" -f $zipHash, (Split-Path -Leaf $zip) | Set-Content "$enc.sha256" -Encoding ascii

# -- 4. remove plaintext only after the proof --
Remove-Item $zip -Force
if ($RemovePlaintext) { Remove-Item -Recurse -Force $BackupDir; Write-Host "plaintext folder removed: $BackupDir" } else { Write-Host "plaintext folder kept (use -RemovePlaintext to delete it)" }
Write-Host "RESULT: PASS"
