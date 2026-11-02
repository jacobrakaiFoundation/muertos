#!/usr/bin/env bash
# Rebuild one el7 source package unchanged: ./rebuild.sh <package>
set -euo pipefail

pkg="$1"
root="$(cd "$(dirname "$0")" && pwd)"

docker build --platform linux/amd64 -t muertos-build:el7 "$root/build"
mkdir -p "$root/out"
docker run --rm --platform linux/amd64 -v "$root/out:/out" muertos-build:el7 \
  rebuild-in-container "$pkg"
