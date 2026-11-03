#!/usr/bin/env bash
# Vault packages with our security patches, each task in a container:
#   ./backport.sh build <package>   build into out/<package>/
#   ./backport.sh test <package>    run packages/<package>/test.sh on stock centos:7.9.2009
# packages/<package>/ holds the patched spec, our patches and the test; everything else
# comes from the signed vault SRPM.
set -euo pipefail

task="$1"
pkg="$2"
root="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$root/packages/$pkg/$pkg.spec" ]; then
  echo "no packages/$pkg/$pkg.spec" >&2
  exit 2
fi
mkdir -p "$root/out"
case "$task" in
  build)
    docker build --platform linux/amd64 -t muertos-build:el7 "$root/build"
    docker run --rm --platform linux/amd64 -v "$root:/src:ro" -v "$root/out:/out" \
      muertos-build:el7 bash /src/packages/backport-in-container.sh "$pkg"
    ;;
  test)
    # A tun device and NET_ADMIN let tests exercise tunnel forwarding (openssh).
    docker run --rm --platform linux/amd64 --cap-add NET_ADMIN --device /dev/net/tun \
      -v "$root:/src:ro" centos:7.9.2009 \
      bash "/src/packages/$pkg/test.sh" "/src/out/$pkg"
    ;;
  *) echo "unknown task '$task': expected build or test" >&2; exit 2 ;;
esac
