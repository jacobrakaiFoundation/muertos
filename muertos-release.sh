#!/usr/bin/env bash
# muertos-release tasks, each in a container:
#   ./muertos-release.sh build   build the noarch RPM into out/muertos-release/
#   ./muertos-release.sh test    install it on a stock centos:7.9.2009 image and check yum
set -euo pipefail

task="$1"
root="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$root/out"
case "$task" in
  build)
    docker build --platform linux/amd64 -t muertos-build:el7 "$root/build"
    docker run --rm --platform linux/amd64 -v "$root:/src:ro" -v "$root/out:/out" \
      muertos-build:el7 bash /src/muertos-release/build-in-container.sh
    ;;
  test)
    docker run --rm --platform linux/amd64 -v "$root:/src:ro" centos:7.9.2009 \
      bash /src/tests/release-checks.sh /src/out/muertos-release
    ;;
  *) echo "unknown task '$task': expected build or test" >&2; exit 2 ;;
esac
