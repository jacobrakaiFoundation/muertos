#!/usr/bin/env bash
# Run once, by the owner, on the mini with a YubiKey (OpenPGP applet) plugged in.
# The signing key is generated ON the card and cannot be exported or backed up; losing the
# card means issuing a new key and a new muertos-release. Only the public half is committed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export GNUPGHOME="$HOME/.muertos-gnupg"
[ ! -d "$GNUPGHOME" ] || { echo "$GNUPGHOME already exists; refusing to create a second key" >&2; exit 1; }
mkdir -m 700 "$GNUPGHOME"

# Tools the release flow needs: pinentry-mac shows the PIN prompt without a terminal.
for formula in pinentry-mac rpm createrepo_c ykman; do
  brew list --formula "$formula" > /dev/null 2>&1 || brew install "$formula"
done
echo "pinentry-program $(brew --prefix)/bin/pinentry-mac" > "$GNUPGHOME/gpg-agent.conf"
gpgconf --kill gpg-agent

gpg --card-status > /dev/null || { echo "no OpenPGP card found" >&2; exit 1; }
cat <<'MSG'
In the gpg prompt: type  admin, then  key-attr (choose RSA 4096 for Signature),
then  generate  (say NO to an off-card backup, set a 5y expiry, name "muertos signing key").
Change the default PINs first (passwd) and set touch policy:  ykman openpgp keys set-touch sig on
MSG
gpg --edit-card

fpr="$(gpg --list-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')"
gpg --armor --export "$fpr" > "$root/release/RPM-GPG-KEY-muertos"
echo "$fpr" > "$root/release/signing-key.fpr"
echo "fingerprint: $fpr  (commit release/RPM-GPG-KEY-muertos and signing-key.fpr)"
