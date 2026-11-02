#!/usr/bin/env bash
# Fetch a signed SRPM from vault, verify it, install its build deps, and
# rebuild it unprivileged. Results land in /out/<package>/.
set -euo pipefail

pkg="$1"
work="$(mktemp -d)"
cd "$work"

yumdownloader --source "$pkg"
srpm="$(ls ./*.src.rpm)"
rpm -K "$srpm"
yum-builddep -y "$srpm"

chown -R builder "$work"
runuser -u builder -- rpmbuild --rebuild --define "_topdir $work/rpmbuild" "$srpm"

mkdir -p "/out/$pkg"
cp "$srpm" "/out/$pkg/"
find "$work/rpmbuild/RPMS" -name '*.rpm' -exec cp {} "/out/$pkg/" \;
ls -l "/out/$pkg"
