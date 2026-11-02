#!/usr/bin/env bash
# Runs as root inside the booted guest:
#   ./guest-checks.sh <expected uname -r> <file of units already failed on the stock kernel>
# Pass criteria from docs/kernel.md.
set -euo pipefail

expected_kernel="$1"
stock_failed_units="$2"

check() {
  echo "CHECK $1"
}

check "running kernel is $expected_kernel"
test "$(uname -r)" = "$expected_kernel"

check "no failed systemd units beyond the stock kernel's"
failed="$(systemctl --failed --no-legend | awk '{print $1}' | grep -vxF -f "$stock_failed_units" || true)"
if [ -n "$failed" ]; then
  systemctl --failed --no-legend
  echo "kernel command line: $(cat /proc/cmdline)"
  for unit in $failed; do
    echo "--- journal for $unit"
    journalctl -b --no-pager -u "$unit" | tail -40
  done
  exit 1
fi

check "SELinux enforcing"
test "$(getenforce)" = Enforcing

check "XFS root"
test "$(findmnt -n -o FSTYPE /)" = xfs

check "sshd active"
systemctl is-active sshd

check "firewalld starts and loads rules"
yum -y -q install firewalld
systemctl start firewalld
firewall-cmd --state
firewall-cmd --add-service=http
firewall-cmd --list-services | grep -qw http

check "docker-ce runs a container"
bash docker-check.sh

echo "kernel error-level messages (informational):"
dmesg --level=err,crit,alert,emerg || true
echo "ALL CHECKS PASSED on $(uname -r)"
