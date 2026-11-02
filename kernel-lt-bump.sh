#!/usr/bin/env bash
# Move kernel-lt to a newer 6.12.y stable release:
#   ./kernel-lt-bump.sh 6.12.116
# Sets Version and resets Release in kernel/kernel-lt.spec, takes the tarball's sha256 from
# kernel.org's signed sha256sums.asc, and regenerates kernel/config-x86_64.
set -euo pipefail

version="$1"
root="$(cd "$(dirname "$0")" && pwd)"
spec="$root/kernel/kernel-lt.spec"
# Kernel.org checksum autosigner, published in https://git.kernel.org/pub/scm/docs/kernel/pgpkeys.git
signer=B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1
current="$(awk '/^Version:/ {print $2}' "$spec")"

if [[ ! "$version" =~ ^6\.12\.[0-9]+$ ]]; then
  echo "version '$version' is not a 6.12.y release" >&2; exit 2
fi
if [ "$version" = "$current" ] || [ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)" != "$version" ]; then
  echo "version $version is not newer than the spec's $current" >&2; exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/signer.asc" "https://git.kernel.org/pub/scm/docs/kernel/pgpkeys.git/plain/keys/${signer: -16}.asc"
gpg --dearmor < "$work/signer.asc" > "$work/signer.gpg"
curl -fsSL -o "$work/sha256sums.asc" https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
if ! gpgv --keyring "$work/signer.gpg" --status-fd 3 --output - "$work/sha256sums.asc" 3>"$work/status" > "$work/sha256sums"; then
  echo "sha256sums.asc failed signature verification against $signer:" >&2; cat "$work/status" >&2; exit 1
fi
if ! grep -qE "^\[GNUPG:\] VALIDSIG .* $signer\$" "$work/status"; then
  echo "sha256sums.asc is not signed by $signer:" >&2; cat "$work/status" >&2; exit 1
fi

# Read only the verified plaintext, never the raw .asc.
if ! line="$(grep -E "^[0-9a-f]{64}  linux-$version\.tar\.xz\$" "$work/sha256sums")"; then
  echo "no sha256 for linux-$version.tar.xz in the signed sha256sums.asc" >&2; exit 1
fi
echo "$line" > "$root/kernel/sources.sha256"
sed -i.bak -e "s/^Version: .*/Version: $version/" -e 's/^Release: .*/Release: 1%{?dist}/' "$spec"
rm "$spec.bak"

"$root/kernel.sh" config
echo "kernel-lt moved from $current to $version"
