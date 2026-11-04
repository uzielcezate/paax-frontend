# Restoring the portable PAAX backup on another Windows machine

The portable copy `<date>-pre-demo.portable.paaxbak` depends on nothing from the original machine: no DPAPI key, no
Windows account, no Supabase access. You need the file, its recovery passphrase, and the two scripts
`Unprotect-Backup.ps1` + `Expand-Archive` (built into Windows PowerShell 5.1+). Keep `Unprotect-Backup.ps1` (and
`Verify-Restore.ps1`, `scratch_db_fixtures.sql`, `06_backup_fingerprint.sql`) next to the file on the offline media.

## File format (so it can be opened even without the script)

`"PAAXBAK1"` (8 bytes) | mode (1 byte: 2 = passphrase) | salt (16) | IV (16) | AES-256-CBC/PKCS7 ciphertext |
HMAC-SHA256 (32) over everything before it. Key = PBKDF2-HMAC-SHA256(passphrase, salt, 300000 iterations, 64 bytes):
first 32 bytes AES key, last 32 bytes HMAC key. Plaintext is a ZIP of the backup folder.

## Steps

```powershell
# 1. integrity of the file you copied (compare with the sha256 printed when it was made / in the .sha256 file)
Get-FileHash .\2026-11-03_1349-pre-demo.portable.paaxbak -Algorithm SHA256

# 2. decrypt (prompts for the recovery passphrase; HMAC is verified before anything is written)
powershell -ExecutionPolicy Bypass -File .\Unprotect-Backup.ps1 -EncryptedFile .\2026-11-03_1349-pre-demo.portable.paaxbak -OutFile .\backup.zip

# 3. unpack
Expand-Archive .\backup.zip -DestinationPath .\2026-11-03_1349-pre-demo
```

The folder then contains: `roles.sql`, `schema.sql`, `managed_schema.sql`, `data.sql` (all rows incl. auth),
`auth_data.sql`, `storage_data.sql`, `fp_production.txt`, `preflight_production.txt`, `SHA256SUMS.txt`,
`storage\music-images\...` (all object files) and `storage_manifest.csv`.

## Verifying it is a faithful backup (optional, needs Docker Desktop)

`Verify-Restore.ps1 -BackupDir .\2026-11-03_1349-pre-demo` restores it into an isolated Supabase Postgres container
and must print `FINGERPRINTS IDENTICAL` and `RESULT: PASS` (compares with `fp_production.txt` inside the folder).

## Restoring data into a Supabase project (disaster only, separate explicit review)

Order: `managed_schema.sql` -> `schema.sql` -> `managed_schema.sql` again (two auth triggers) -> `data.sql` into an
EMPTY project (or truncate the affected tables first). Storage files are re-uploaded to bucket `music-images` with the
same paths from `storage_manifest.csv`; bucket definitions and the 8 policies are in `storage_data.sql` /
`managed_schema.sql`. Never do this against the live project without a fresh backup and a reviewed plan.

## Where to keep the portable copy

- Two copies on two separate offline media (USB sticks or an external SSD), each verified with `Get-FileHash`
  after copying; one kept at home, one elsewhere (e.g. a trusted relative's place or a safe).
- The passphrase in a different place from the media: a password manager entry and/or a paper copy in a sealed
  envelope. Never together with the stick, never in the repo, OneDrive or chat.
- Not in cloud storage: it contains password hashes, refresh tokens and e-mails. If a cloud copy is ever wanted,
  only this encrypted file, never the plaintext folder.
- Refresh the copy after any later backup; delete superseded copies by overwriting the media or `cipher /w:` on the
  drive letter.
