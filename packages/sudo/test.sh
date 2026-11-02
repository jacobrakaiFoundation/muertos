#!/usr/bin/env bash
# Runs as root in a stock centos:7.9.2009 container: ./test.sh <dir with our sudo RPM>
# Installs el7's last sudo from vault, upgrades it to ours with rpm -Uvh, and checks
# each backported CVE as an unprivileged user.
set -euo pipefail

rpm_dir="$1"

check() {
  echo "CHECK $1"
}

rm -f /etc/yum.repos.d/*.repo
cp /src/build/vault.repo /etc/yum.repos.d/
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
yum -y -q --disablerepo='*-source,sclo-rh' install sudo-1.8.23-10.el7_9.3

check "upgrades el7's sudo-1.8.23-10.el7_9.3"
rpm -Uvh "$(ls "$rpm_dir"/sudo-1.8.23-*.x86_64.rpm | grep -v devel)"
rpm -q sudo | grep -qx 'sudo-1.8.23-10.el7_9.3.muertos1.x86_64'

useradd alice
as_alice() {
  runuser -u alice -- "$@"
}

check "CVE-2025-32462: -h runs no command, but still lists"
echo 'alice otherhost = NOPASSWD: ALL' > /etc/sudoers.d/remote
chmod 440 /etc/sudoers.d/remote
if out="$(as_alice sudo -n -h otherhost id -u 2>&1)"; then
  echo "ran a command for another host: $out" >&2
  exit 1
fi
echo "$out" | grep -q 'a remote host may only be specified when listing privileges'
as_alice sudo -n -l -h otherhost | grep -q '(root) NOPASSWD: ALL'
rm /etc/sudoers.d/remote

check "CVE-2026-96512: a user TZ does not extend an expired NOTAFTER"
expired="$(date -u -d '1 hour ago' +%Y%m%d%H%M%S)"
echo "alice ALL = NOTAFTER=$expired NOPASSWD: ALL" > /etc/sudoers.d/expired
chmod 440 /etc/sudoers.d/expired
# UTC-12 reads the zone-less timestamp 12h later, which would still be in the future.
if out="$(as_alice env TZ=Etc/GMT+12 sudo -n id -u 2>&1)"; then
  echo "expired rule allowed with a user TZ: $out" >&2
  exit 1
fi
rm /etc/sudoers.d/expired

check "CVE-2026-96512: plugins still get the user's TZ for env_keep"
cat > /etc/sudoers.d/tz <<'EOF'
Defaults env_keep += TZ
alice ALL = NOPASSWD: /usr/bin/env
EOF
chmod 440 /etc/sudoers.d/tz
as_alice env TZ=Etc/GMT+12 sudo -n /usr/bin/env | grep -qx 'TZ=Etc/GMT+12'
rm /etc/sudoers.d/tz

check "CVE-2026-35535: mailer runs with root's uid, gid and groups only"
cat > /usr/local/bin/record-mailer <<'EOF'
#!/bin/sh
id > /tmp/mailer-id
cat > /dev/null
EOF
chmod 755 /usr/local/bin/record-mailer
cat > /etc/sudoers.d/mail <<'EOF'
Defaults mail_always, mailto=root, mailerpath=/usr/local/bin/record-mailer
alice ALL = NOPASSWD: /usr/bin/true
EOF
chmod 440 /etc/sudoers.d/mail
as_alice sudo -n /usr/bin/true
for _ in $(seq 50); do
  [ -s /tmp/mailer-id ] && break
  sleep 0.1
done
cat /tmp/mailer-id
grep -qx 'uid=0(root) gid=0(root) groups=0(root)' /tmp/mailer-id

echo "ALL CHECKS PASSED"
