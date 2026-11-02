#!/usr/bin/env bash
# Sign every RPM in /repo/x86_64, build repo metadata, and detach-sign repomd.xml.
# Expects FPR and PASS in the environment and a secret keyring export at /gnupg/secret.gpg.
set -euo pipefail

export GNUPGHOME=/tmp/gnupg
mkdir -m 700 "$GNUPGHOME"
echo "allow-loopback-pinentry" > "$GNUPGHOME/gpg-agent.conf"
gpg --batch --import /gnupg/secret.gpg

cat > ~/.rpmmacros <<EOF
%_gpg_name $FPR
%__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor --pinentry-mode loopback --passphrase-fd 3 --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}
EOF

for rpm in /repo/x86_64/*.rpm; do
  rpmsign --addsign "$rpm" 3<<<"$PASS"
done
rpm --import /release/RPM-GPG-KEY-muertos
rpm -K /repo/x86_64/*.rpm | grep -v 'digests signatures OK' && { echo "unsigned or bad RPM above" >&2; exit 1; } || true

createrepo --general-compress-type=gz /repo
gpg --batch --pinentry-mode loopback --passphrase-fd 3 -u "$FPR" --detach-sign --armor \
  -o /repo/repodata/repomd.xml.asc /repo/repodata/repomd.xml 3<<<"$PASS"
ls /repo/repodata
