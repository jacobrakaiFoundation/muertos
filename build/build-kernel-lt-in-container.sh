#!/usr/bin/env bash
# Build the kernel-lt RPM from /kernel unprivileged. Results land in /out/kernel-lt/.
set -euo pipefail

cd /kernel/sources && sha256sum -c ../sources.sha256
yum-builddep -y /kernel/kernel-lt.spec

top=/home/builder/rpmbuild
mkdir -p "$top/SOURCES"
cp /kernel/sources/linux-*.tar.xz /kernel/config-x86_64 "$top/SOURCES/"
chown -R builder "$top"
runuser -u builder -- rpmbuild -bb --define "_topdir $top" /kernel/kernel-lt.spec

mkdir -p /out/kernel-lt
cp "$top"/RPMS/x86_64/*.rpm /out/kernel-lt/
ls -l /out/kernel-lt
