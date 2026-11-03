#!/usr/bin/env bash
# Runs as root in a stock centos:7.9.2009 container: ./test.sh <dir with our openssh RPMs>
# Installs el7's last openssh from vault, upgrades it to ours with rpm -Uvh, and checks
# each backported CVE.
set -euo pipefail

rpm_dir="$1"
rel=7.4p1-23.el7_9

check() {
  echo "CHECK $1"
}

rm -f /etc/yum.repos.d/*.repo
cp /src/build/vault.repo /etc/yum.repos.d/
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
yum -y -q --disablerepo='*-source,sclo-rh' install \
  "openssh-$rel" "openssh-clients-$rel" "openssh-server-$rel"

check "upgrades el7's openssh-$rel"
rpm -Uvh "$rpm_dir"/openssh-7.4p1-*.x86_64.rpm "$rpm_dir"/openssh-clients-7.4p1-*.x86_64.rpm \
  "$rpm_dir"/openssh-server-7.4p1-*.x86_64.rpm
for p in openssh openssh-clients openssh-server; do
  rpm -q "$p" | grep -qx "$p-$rel.muertos1.x86_64"
done

check "CVE-2026-35385: scp download as root drops setuid/setgid unless -p"
# A stand-in for ssh that runs the remote scp command locally, so no sshd is needed.
cat > /usr/local/bin/local-ssh <<'EOF'
#!/bin/sh
while [ "$1" != fakehost ]; do shift; done
shift
exec sh -c "$*"
EOF
chmod 755 /usr/local/bin/local-ssh
install -m 6755 /dev/null /tmp/suid-src
mkdir /tmp/dl /tmp/dl-p
scp -S /usr/local/bin/local-ssh fakehost:/tmp/suid-src /tmp/dl/
stat -c %a /tmp/dl/suid-src | grep -qx 755
scp -p -S /usr/local/bin/local-ssh fakehost:/tmp/suid-src /tmp/dl-p/
stat -c %a /tmp/dl-p/suid-src | grep -qx 6755

check "CVE-2026-59999: DisableForwarding=yes refuses tunnels despite PermitTunnel=yes"
[ -c /dev/net/tun ]
ssh-keygen -A
ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519
cp /root/.ssh/id_ed25519.pub /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
tunnel_log() {
  local port="$1" disable="$2"
  /usr/sbin/sshd -p "$port" -o PermitRootLogin=yes -o PermitTunnel=yes \
    -o DisableForwarding="$disable" -o UsePAM=no
  for _ in $(seq 50); do
    ssh-keyscan -p "$port" 127.0.0.1 > /dev/null 2>&1 && break
    sleep 0.1
  done
  # An accepted tunnel keeps the session open, so the timeout ends it either way.
  timeout 15 ssh -vv -w any -o StrictHostKeyChecking=no -o BatchMode=yes -p "$port" \
    root@127.0.0.1 true 2>&1 || true
}
# Control: with forwarding allowed the same request opens the tunnel (channel 0).
tunnel_log 2201 no | grep -q 'channel 0: open confirm'
tunnel_log 2202 yes | grep -q 'Server has rejected tunnel device forwarding'

echo "ALL CHECKS PASSED"
