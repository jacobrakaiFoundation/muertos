#!/usr/bin/env bash
# Run once, by the owner, on the mini. Creates the muertos signing key in a dedicated
# GnuPG home (~/.muertos-gnupg) and commits only the public half.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export GNUPGHOME="$HOME/.muertos-gnupg"

if [ -d "$GNUPGHOME" ]; then
  echo "$GNUPGHOME already exists; refusing to create a second key" >&2
  exit 1
fi
mkdir -m 700 "$GNUPGHOME"

# gpg prompts for the passphrase itself; it never passes through this script.
gpg --quick-generate-key "muertos signing key <jacob.e.durham@gmail.com>" rsa4096 sign 5y
fpr="$(gpg --list-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')"

gpg --armor --export "$fpr" > "$root/release/RPM-GPG-KEY-muertos"
echo "$fpr" > "$root/release/signing-key.fpr"
gpg --armor --export-secret-keys "$fpr" > "$HOME/muertos-signing-key-BACKUP.asc"
chmod 600 "$HOME/muertos-signing-key-BACKUP.asc"

echo "fingerprint: $fpr"
echo "Public key: release/RPM-GPG-KEY-muertos (commit it)."
echo "Move ~/muertos-signing-key-BACKUP.asc to offline storage, then delete it from this disk."
