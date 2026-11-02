#!/usr/bin/env bash
# kernel-lt tasks, each in the el7 build container:
#   ./kernel.sh config   regenerate kernel/config-x86_64
#   ./kernel.sh build    build the RPM into out/kernel-lt/
set -euo pipefail

task="$1"
root="$(cd "$(dirname "$0")" && pwd)"
version="$(awk '/^Version:/ {print $2}' "$root/kernel/kernel-lt.spec")"
tarball="$root/kernel/sources/linux-$version.tar.xz"

mkdir -p "$root/kernel/sources" "$root/out"
if [ ! -f "$tarball" ]; then
  curl -fL -o "$tarball" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$version.tar.xz"
fi

docker build --platform linux/amd64 -t muertos-build:el7 "$root/build"
case "$task" in
  config) cmd=update-kernel-config-in-container ;;
  build) cmd=build-kernel-lt-in-container ;;
  *) echo "unknown task '$task': expected config or build" >&2; exit 2 ;;
esac
docker run --rm --platform linux/amd64 -v "$root/kernel:/kernel" -v "$root/out:/out" \
  muertos-build:el7 "$cmd"
