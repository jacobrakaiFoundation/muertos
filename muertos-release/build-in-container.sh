#!/usr/bin/env bash
# Build the muertos-release RPM from /src unprivileged. Results land in /out/muertos-release/.
set -euo pipefail

top=/home/builder/rpmbuild
mkdir -p "$top/SOURCES"
cp /src/muertos-release/muertos.repo /src/release/RPM-GPG-KEY-muertos "$top/SOURCES/"
chown -R builder "$top"
runuser -u builder -- rpmbuild -bb --define "_topdir $top" /src/muertos-release/muertos-release.spec

mkdir -p /out/muertos-release
cp "$top"/RPMS/noarch/*.rpm /out/muertos-release/
ls -l /out/muertos-release
