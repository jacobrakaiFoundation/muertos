#!/usr/bin/env bash
# Sign and publish on the mini. CI only ever builds unsigned RPMs; the private key lives
# in ~/.muertos-gnupg here and never goes to GitHub.
#   ./release/publish-on-mini.sh <CI run id of the kernel-lt/packages workflow>
set -euo pipefail

run_id="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
fpr="$(cat "$root/release/signing-key.fpr")"
stage="$(mktemp -d)"
gnupg="$(mktemp -d)"
chmod 700 "$gnupg"
trap 'rm -rf "$stage" "$gnupg"' EXIT

read -r -s -p "muertos key passphrase: " passphrase
echo

# Fetch the unsigned RPMs CI built.
gh run download "$run_id" --repo jacobrakaiFoundation/muertos --dir "$stage/in"
mkdir -p "$stage/repo/x86_64"
find "$stage/in" -name '*.rpm' -exec cp {} "$stage/repo/x86_64/" \;

# Temporary keyring for the container; removed on exit.
GNUPGHOME="$HOME/.muertos-gnupg" gpg --batch --pinentry-mode loopback \
  --passphrase "$passphrase" --export-secret-keys "$fpr" > "$gnupg/secret.gpg"

docker build --platform linux/amd64 -t muertos-build:el7 "$root/build"
docker run --rm --platform linux/amd64 -e FPR="$fpr" -e PASS="$passphrase" \
  -v "$stage/repo:/repo" -v "$gnupg:/gnupg" -v "$root/release:/release:ro" \
  muertos-build:el7 sign-and-index-in-container

# Publish to the gh-pages branch (GitHub Pages serves it as the yum repo).
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
