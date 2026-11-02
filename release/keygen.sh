#!/usr/bin/env bash
# Run once, by the owner, on the mini with a YubiKey (OpenPGP applet) plugged in.
# The signing key is generated ON the card and cannot be exported or backed up; losing the
# card means issuing a new key and a new muertos-release. Only the public half is committed.
# Safe to rerun until a key exists.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export GNUPGHOME="$HOME/.muertos-gnupg"
mkdir -p -m 700 "$GNUPGHOME"
if gpg --list-secret-keys --with-colons | grep -q '^sec'; then
  echo "$GNUPGHOME already holds a key; refusing to create a second one" >&2
  exit 1
fi

# Tools the release flow needs: pinentry-mac shows the PIN prompt without a terminal and
# offers "Save in Keychain" (gpg-agent allows that external cache by default).
for formula in pinentry-mac rpm ykman; do
  brew list --formula "$formula" > /dev/null 2>&1 || brew install "$formula"
done
echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" > "$GNUPGHOME/gpg-agent.conf"
gpgconf --kill gpg-agent

gpg --card-status > /dev/null || { echo "no OpenPGP card found" >&2; exit 1; }
cat <<'MSG'
At gpg/card>, in order:
  admin
  passwd     1 = PIN (default 123456), 3 = Admin PIN (default 12345678), then Q
             Type PINs in the pop-up. Tick "Save in Keychain" for the PIN only, never the Admin PIN.
  key-attr   RSA, 4096 for Signature; Enter to keep the other two slots
  generate   n to off-card backup, 5y expiry, name "muertos signing key"
  quit
MSG
gpg --edit-card

fpr="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')"
if [ -z "$fpr" ]; then
  echo "no key was generated on the card; rerun ./release/keygen.sh" >&2
  exit 1
fi
gpg --armor --export "$fpr" > "$root/release/RPM-GPG-KEY-muertos"
echo "$fpr" > "$root/release/signing-key.fpr"
ykman openpgp keys set-touch sig on
echo "fingerprint: $fpr  (commit release/RPM-GPG-KEY-muertos and signing-key.fpr)"
