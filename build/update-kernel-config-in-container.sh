#!/usr/bin/env bash
# Regenerate /kernel/config-x86_64: the latest el7 3.10 kernel config, carried
# forward to the kernel-lt version by olddefconfig, with /kernel/config-overrides on top.
set -euo pipefail

cd /kernel/sources && sha256sum -c ../sources.sha256
yum-builddep -y /kernel/kernel-lt.spec
export PATH=/opt/rh/devtoolset-11/root/usr/bin:$PATH

work="$(mktemp -d)"
cd "$work"
yumdownloader kernel
rpm2cpio kernel-3.10.0-*.rpm | cpio -idm --quiet './boot/config-*'
tar xJf /kernel/sources/linux-*.tar.xz
cd linux-*

cp "$work"/boot/config-* .config
make olddefconfig
scripts/kconfig/merge_config.sh -m .config /kernel/config-overrides
make olddefconfig

grep -v -E '^\s*$|^# [^C]|^#$' /kernel/config-overrides | while IFS= read -r line; do
  grep -qxF "$line" .config || { echo "override did not apply: $line" >&2; exit 1; }
done
cp .config /kernel/config-x86_64
echo "wrote /kernel/config-x86_64 from $(ls "$work"/boot/config-*)"
