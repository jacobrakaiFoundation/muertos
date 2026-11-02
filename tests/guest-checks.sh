#!/usr/bin/env bash
# Runs as root inside the booted guest: ./guest-checks.sh <expected uname -r>
# Pass criteria from docs/kernel.md.
set -euo pipefail

expected_kernel="$1"

check() {
  echo "CHECK $1"
}

check "running kernel is $expected_kernel"
test "$(uname -r)" = "$expected_kernel"

check "no failed systemd units"
failed="$(systemctl --failed --no-legend)"
if [ -n "$failed" ]; then
  echo "$failed"
  echo "kernel command line: $(cat /proc/cmdline)"
  for unit in $(echo "$failed" | awk '{print $1}'); do
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
yum -y -q install yum-utils
yum-config-manager -q --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum -y -q install docker-ce
systemctl start docker
docker run --rm -p 8080:80 -d --name web nginx:alpine
sleep 3
curl -fsS -o /dev/null http://127.0.0.1:8080/
docker rm -f web

echo "kernel error-level messages (informational):"
dmesg --level=err,crit,alert,emerg || true
echo "ALL CHECKS PASSED on $(uname -r)"
