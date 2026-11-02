#!/usr/bin/env bash
# Boot a stock CentOS 7.9 cloud VM under KVM, install a kernel-lt RPM the way a user
# would (yum localinstall), reboot into it, and run tests/guest-checks.sh.
# Needs: Linux host with /dev/kvm, qemu-system-x86_64, qemu-img, cloud-localds, ssh.
#   ./tests/boot-test.sh <kernel-lt rpm> <work dir>
set -euo pipefail

rpm_path="$(realpath "$1")"
work="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
image_url=https://cloud.centos.org/centos/7/images
image=CentOS-7-x86_64-GenericCloud-2009.qcow2
ssh_port=2222

mkdir -p "$work"
cd "$work"

if [ ! -f "$image" ]; then
  curl -fsSL -o "$image" "$image_url/$image"
fi
curl -fsSL "$image_url/sha256sum.txt" | grep " $image\$" | sha256sum -c -

qemu-img create -q -f qcow2 -b "$image" -F qcow2 disk.qcow2 20G
rm -f id_ed25519 id_ed25519.pub
ssh-keygen -q -t ed25519 -N '' -f id_ed25519
cat > user-data <<EOF
#cloud-config
ssh_authorized_keys:
  - $(cat id_ed25519.pub)
EOF
cloud-localds seed.iso user-data

ssh_opts=(-i id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=5 -o LogLevel=ERROR)
guest() {
  ssh "${ssh_opts[@]}" -p "$ssh_port" centos@127.0.0.1 "$@"
}

wait_for_ssh() {
  local deadline=$((SECONDS + 300))
  until guest true 2>/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "guest ssh not up after 300s; console tail:" >&2
      tail -50 console.log >&2
      exit 1
    fi
    sleep 5
  done
}

stop_vm() {
  if [ -f qemu.pid ]; then
    kill "$(cat qemu.pid)" 2>/dev/null || true
  fi
}
trap stop_vm EXIT

qemu-system-x86_64 -enable-kvm -cpu host -m 4096 -smp 2 \
  -drive file=disk.qcow2,if=virtio -drive file=seed.iso,if=virtio,format=raw \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$ssh_port-:22 \
  -display none -serial file:console.log -daemonize -pidfile qemu.pid

wait_for_ssh
echo "stock kernel: $(guest uname -r)"

scp "${ssh_opts[@]}" -P "$ssh_port" "$rpm_path" "$root/build/vault.repo" "$root/tests/guest-checks.sh" \
  centos@127.0.0.1:
guest sudo sh -c 'rm -f /etc/yum.repos.d/*.repo && cp vault.repo /etc/yum.repos.d/'
guest sudo yum -y localinstall "$(basename "$rpm_path")"
expected="$(guest rpm -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$(basename "$rpm_path")")"
echo "default boot entry: $(guest sudo grubby --default-kernel)"

guest sudo systemctl reboot || true
sleep 15
wait_for_ssh
guest sudo bash guest-checks.sh "$expected"
