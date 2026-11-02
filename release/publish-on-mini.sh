#!/usr/bin/env bash
# Sign and publish on the mini with the YubiKey. CI only builds unsigned RPMs; the key
# never leaves the card. Each signature needs a PIN and a touch.
# Needs (brew install rpm): rpmsign on the host; repo metadata is built in the el7 container.
#   ./release/publish-on-mini.sh <CI run id>...
# Each publish replaces el7/ whole, so pass a run for every workflow that ships RPMs
# (kernel-lt, muertos-release).
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <CI run id>..." >&2
  exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
fpr="$(cat "$root/release/signing-key.fpr")"
export GNUPGHOME="$HOME/.muertos-gnupg"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

for run_id in "$@"; do
  gh run download "$run_id" --repo jacobrakaiFoundation/muertos --dir "$stage/in/$run_id"
done
# Runs land in one flat directory; the same file name from two runs means two runs of
# one workflow were passed, and one build would silently replace the other.
dupes="$(find "$stage/in" -name '*.rpm' -exec basename {} \; | sort | uniq -d)"
if [ -n "$dupes" ]; then
  echo "same RPM in more than one run ($*); pass one run per workflow:" >&2
  echo "$dupes" >&2
  exit 1
fi
mkdir -p "$stage/repo/x86_64"
find "$stage/in" -name '*.rpm' -exec cp {} "$stage/repo/x86_64/" \;

for rpm in "$stage"/repo/x86_64/*.rpm; do
  rpmsign --define "_gpg_name $fpr" --addsign "$rpm"
done
# Verify with the committed public key in a throwaway rpm db.
rpmkeys --dbpath "$stage/db" --import "$root/release/RPM-GPG-KEY-muertos"
rpmkeys --dbpath "$stage/db" --checksig "$stage"/repo/x86_64/*.rpm | grep -v ' signatures OK' \
  && { echo "bad or unsigned RPM above" >&2; exit 1; } || true

docker build --platform linux/amd64 -t muertos-build:el7 "$root/build"
docker run --rm --platform linux/amd64 -v "$stage/repo:/repo" muertos-build:el7 \
  createrepo --general-compress-type=gz /repo
gpg --detach-sign --armor -u "$fpr" -o "$stage/repo/repodata/repomd.xml.asc" "$stage/repo/repodata/repomd.xml"

git -C "$root" fetch -q origin gh-pages 2>/dev/null || true
pages="$(mktemp -d)"
git -C "$root" worktree add -q "$pages" origin/gh-pages 2>/dev/null \
  || git -C "$root" worktree add -q --detach "$pages"
rm -rf "${pages:?}/el7" && mkdir -p "$pages/el7"
cp -R "$stage/repo/." "$pages/el7/"
cp "$root/release/RPM-GPG-KEY-muertos" "$pages/"
git -C "$pages" add -A
git -C "$pages" commit -q -m "Publish runs $*"
echo "Review $pages, then: git -C $pages push origin HEAD:gh-pages"
