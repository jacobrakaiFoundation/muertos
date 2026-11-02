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
yum -y -q install yum-utils
yum-config-manager -q --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum -y -q install docker-ce
systemctl start docker
docker run -p 8080:80 -d --name web nginx:alpine
# Wait for nginx rather than a fixed sleep; on failure, the container IP check tells
# "nginx is not up" apart from "port publishing is broken on this kernel".
for _ in $(seq 30); do
  curl -fsS -o /dev/null http://127.0.0.1:8080/ && break
  sleep 1
done
if ! curl -fsS -o /dev/null http://127.0.0.1:8080/; then
  docker ps -a
  docker logs web
  echo "container state: $(docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' web)"
  web_ip="$(docker inspect -f '{{.NetworkSettings.IPAddress}}' web)"
  if [ -n "$web_ip" ]; then
    echo "curl container IP $web_ip:80 directly:"
    curl -sS -o /dev/null -w '%{http_code}\n' "http://$web_ip:80/" || true
  else
    echo "container has no IP; it is not running"
  fi
  echo "listening on 8080:"
  ss -ltnp | grep ':8080' || echo "(nothing)"
  iptables -t nat -S
  # An EPERM inside the container points at the storage driver or SELinux on this kernel.
  docker info --format 'storage driver: {{.Driver}} {{.DriverStatus}}; security: {{.SecurityOptions}}'
  echo "container-selinux: $(rpm -q container-selinux || true)"
  echo "SELinux AVC denials this boot:"
  ausearch -m avc,user_avc -ts boot -i || echo "(none)"
  echo "write /run/nginx.pid in the image, enforcing then permissive:"
  docker run --rm nginx:alpine sh -c 'echo 1 > /run/nginx.pid && echo writable' || true
  setenforce 0
  docker run --rm nginx:alpine sh -c 'echo 1 > /run/nginx.pid && echo writable' || true
  setenforce 1
  exit 1
fi
docker rm -f web

echo "kernel error-level messages (informational):"
dmesg --level=err,crit,alert,emerg || true
echo "ALL CHECKS PASSED on $(uname -r)"
