#!/usr/bin/env bash
# Sign and publish on the mini with the YubiKey. CI only builds unsigned RPMs; the key
# never leaves the card. Each signature needs a PIN and a touch.
# Needs (brew install rpm createrepo_c):  rpmsign, createrepo_c on the host.
#   ./release/publish-on-mini.sh <CI run id>
set -euo pipefail

run_id="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
fpr="$(cat "$root/release/signing-key.fpr")"
export GNUPGHOME="$HOME/.muertos-gnupg"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

gh run download "$run_id" --repo jacobrakaiFoundation/muertos --dir "$stage/in"
mkdir -p "$stage/repo/x86_64"
find "$stage/in" -name '*.rpm' -exec cp {} "$stage/repo/x86_64/" \;

for rpm in "$stage"/repo/x86_64/*.rpm; do
  rpmsign --define "_gpg_name $fpr" --addsign "$rpm"
done
# Verify with the committed public key in a throwaway rpm db.
rpmkeys --dbpath "$stage/db" --import "$root/release/RPM-GPG-KEY-muertos"
rpmkeys --dbpath "$stage/db" --checksig "$stage"/repo/x86_64/*.rpm | grep -v ' signatures OK' \
  && { echo "bad or unsigned RPM above" >&2; exit 1; } || true

createrepo_c "$stage/repo"
gpg --detach-sign --armor -u "$fpr" -o "$stage/repo/repodata/repomd.xml.asc" "$stage/repo/repodata/repomd.xml"

git -C "$root" fetch -q origin gh-pages 2>/dev/null || true
pages="$(mktemp -d)"
git -C "$root" worktree add -q "$pages" origin/gh-pages 2>/dev/null \
  || git -C "$root" worktree add -q --detach "$pages"
rm -rf "${pages:?}/el7" && mkdir -p "$pages/el7"
cp -R "$stage/repo/." "$pages/el7/"
cp "$root/release/RPM-GPG-KEY-muertos" "$pages/"
git -C "$pages" add -A
git -C "$pages" commit -q -m "Publish run $run_id"
echo "Review $pages, then: git -C $pages push origin HEAD:gh-pages"
