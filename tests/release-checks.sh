#!/usr/bin/env bash
# Runs as root in a stock centos:7.9.2009 container: ./release-checks.sh <dir with the RPM>
# Installs muertos-release the documented way (rpm -Uvh), checks yum works against
# vault, then erases it and checks CentOS-Base.repo is back as shipped.
set -euo pipefail

rpm_path="$(ls "$1"/muertos-release-*.noarch.rpm)"
base=/etc/yum.repos.d/CentOS-Base.repo

check() {
  echo "CHECK $1"
}

cp "$base" /tmp/CentOS-Base.repo.orig

check "installs with rpm -Uvh"
rpm -Uvh "$rpm_path"

# repolist still lists the dead CentOS-Base repos (with 0 packages) when they are
# enabled, so requiring exactly the vault repos proves they are off. The muertos repo
# is skipped until the first publish exists on GitHub Pages.
check "yum resolves from vault only"
repos="$(yum -q --disablerepo=muertos repolist enabled | awk 'NR > 1 {print $1}' | cut -d/ -f1)"
echo "$repos"
test "$(echo "$repos" | sort | tr '\n' ' ')" = "vault-base vault-extras vault-updates "
yum -y -q --disablerepo=muertos install tree
rpm -q tree

check "upgrade does not add a second marker"
rpm -Uvh --replacepkgs "$rpm_path"
test "$(grep -c '^# disabled by muertos-release' "$base")" -eq 3

check "erase restores CentOS-Base.repo"
rpm -e muertos-release
cmp "$base" /tmp/CentOS-Base.repo.orig

echo "ALL CHECKS PASSED"
