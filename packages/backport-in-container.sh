#!/usr/bin/env bash
# Fetch and verify a package's vault SRPM, overlay /src/packages/<package>/ (spec and
# patches), and build it unprivileged. Results land in /out/<package>/.
set -euo pipefail

pkg="$1"
top=/home/builder/rpmbuild
work="$(mktemp -d)"
cd "$work"

yumdownloader --source "$pkg"
srpm="$(ls ./*.src.rpm)"
rpm -K "$srpm"

mkdir -p "$top/SOURCES"
rpm2cpio "$srpm" | (cd "$top/SOURCES" && cpio -idm --quiet)
rm "$top/SOURCES/$pkg.spec"
cp /src/packages/"$pkg"/*.patch "$top/SOURCES/"
cp /src/packages/"$pkg"/"$pkg".spec "$top/"

chown -R builder "$top"
# Resolve build deps from our SRPM, not the spec: some specs (ruby) read files from
# %{_sourcedir} while parsing, which only exist under our _topdir.
runuser -u builder -- rpmbuild -bs --define "_topdir $top" "$top/$pkg.spec"
yum-builddep -y "$top"/SRPMS/*.src.rpm
runuser -u builder -- rpmbuild -ba --define "_topdir $top" "$top/$pkg.spec"

mkdir -p "/out/$pkg"
find "$top/RPMS" "$top/SRPMS" -name '*.rpm' -exec cp {} "/out/$pkg/" \;
ls -l "/out/$pkg"
