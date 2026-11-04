# Unprotect-Backup.ps1 - decrypt a .paaxbak produced by Protect-Backup.ps1 back to the .zip (HMAC verified first).
#   powershell -ExecutionPolicy Bypass -File ".\docs\runbooks\demo-release\windows\Unprotect-Backup.ps1" -EncryptedFile <file.paaxbak> [-OutFile <file.zip>]
# dpapi-mode files need the same Windows user on the same machine (backup_key.dpapi); passphrase-mode files prompt.
param(
  [Parameter(Mandatory = $true)][string]$EncryptedFile,
  [string]$OutFile   = "",
  [string]$SecretDir = "C:\Users\uziel\PaaxSecrets",
  [byte[]]$MasterKeyBytes = $null,            # internal: used by Protect-Backup.ps1 for the round-trip proof
  [securestring]$PassphraseSecure = $null     # passphrase-mode files: SecureString handed over in-process instead of a prompt
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
if (-not $OutFile) { $OutFile = [IO.Path]::ChangeExtension($EncryptedFile, '.zip') }
$fs = [IO.File]::OpenRead($EncryptedFile)
try {
  $magic = New-Object byte[] 8;  $fs.Read($magic, 0, 8) | Out-Null
  if ([Text.Encoding]::ASCII.GetString($magic) -ne 'PAAXBAK1') { throw "not a PAAXBAK1 file" }
  $mode = $fs.ReadByte()
  $salt = New-Object byte[] 16; $fs.Read($salt, 0, 16) | Out-Null
  $iv   = New-Object byte[] 16; $fs.Read($iv, 0, 16) | Out-Null
  if ($MasterKeyBytes) { $master = $MasterKeyBytes }
  elseif ($mode -eq 1) { $master = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes((Join-Path $SecretDir 'backup_key.dpapi')), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser) }
  elseif ($mode -eq 2) {
    $sec = if ($PassphraseSecure) { $PassphraseSecure } else { Read-Host -AsSecureString "Backup passphrase" }
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec); $p = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
    $master = (New-Object Security.Cryptography.Rfc2898DeriveBytes($p, $salt, 300000, [Security.Cryptography.HashAlgorithmName]::SHA256)).GetBytes(64); $p = $null
  } else { throw "unknown key mode $mode" }
  $aesKey = $master[0..31]; $macKey = $master[32..63]
  # -- verify HMAC over header + ciphertext before decrypting anything --
  $ctLen = $fs.Length - 41 - 32
  if ($ctLen -lt 16) { throw "file too short" }
  $hmac = New-Object Security.Cryptography.HMACSHA256(,$macKey)
  $header = $magic + [byte[]]@($mode) + $salt + $iv
  $hmac.TransformBlock($header, 0, $header.Length, $null, 0) | Out-Null
  $buf = New-Object byte[] 1048576; $left = $ctLen
  while ($left -gt 0) { $r = $fs.Read($buf, 0, [Math]::Min($buf.Length, $left)); $hmac.TransformBlock($buf, 0, $r, $null, 0) | Out-Null; $left -= $r }
  $hmac.TransformFinalBlock(@(), 0, 0) | Out-Null
  $stored = New-Object byte[] 32; $fs.Read($stored, 0, 32) | Out-Null
  $diff = 0; for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($stored[$i] -bxor $hmac.Hash[$i]) }
  if ($diff -ne 0) { throw "HMAC verification FAILED: wrong key/passphrase or corrupted file; nothing written" }
  # -- decrypt --
  $fs.Position = 41
  $aes = [Security.Cryptography.Aes]::Create(); $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $aesKey; $aes.IV = $iv
  $out = [IO.File]::Create($OutFile)
  $cs  = New-Object Security.Cryptography.CryptoStream($out, $aes.CreateDecryptor(), [Security.Cryptography.CryptoStreamMode]::Write)
  try {
    $left = $ctLen
    while ($left -gt 0) { $r = $fs.Read($buf, 0, [Math]::Min($buf.Length, $left)); $left -= $r; $cs.Write($buf, 0, $r) }
    $cs.FlushFinalBlock()
  } finally { $cs.Close(); $out.Close() }
} finally { $fs.Close() }
Write-Host "decrypted     : $OutFile (HMAC verified)"
