#!/usr/bin/env bash
# Runs as root inside the guest: installs docker-ce, runs nginx with a published port and
# curls it. On failure, prints what tells the likely causes apart and exits 1.
# boot-test.sh runs it on the stock kernel as a baseline; guest-checks.sh runs it on kernel-lt.
#   ./docker-check.sh
set -euo pipefail

yum -y -q install yum-utils
yum-config-manager -q --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum -y -q install docker-ce
systemctl start docker
# Pinned by digest: musl 1.2.6 (current nginx:alpine and nginx:stable-alpine) implements
# pwrite() with pwritev2, which el7's libseccomp 2.3.1 predates, so docker's default seccomp
# profile denies it with EPERM on any el7 kernel. This image is on musl 1.2.5.
image=nginx:1.28-alpine@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236
# Named per kernel, so the stock baseline's container doesn't collide with the kernel-lt run.
name="web-$(uname -r)"
docker run -p 8080:80 -d --name "$name" "$image"
# Wait for nginx rather than a fixed sleep.
for _ in $(seq 30); do
  curl -fsS -o /dev/null http://127.0.0.1:8080/ && break
  sleep 1
done
if ! curl -fsS -o /dev/null http://127.0.0.1:8080/; then
  docker ps -a
  docker logs "$name"
  echo "container state: $(docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' "$name")"
  web_ip="$(docker inspect -f '{{.NetworkSettings.IPAddress}}' "$name")"
  if [ -n "$web_ip" ]; then
    echo "curl container IP $web_ip:80 directly:"
    curl -sS -o /dev/null -w '%{http_code}\n' "http://$web_ip:80/" || true
  else
    echo "container has no IP; it is not running"
  fi
  echo "listening on 8080:"
  ss -ltnp | grep ':8080' || echo "(nothing)"
  iptables -t nat -S
  docker info --format 'storage driver: {{.Driver}} {{.DriverStatus}}; security: {{.SecurityOptions}}'
  echo "versions: $(rpm -q docker-ce containerd.io libseccomp container-selinux | tr '\n' ' ')"
  echo "SELinux AVC denials this boot:"
  ausearch -m avc,user_avc -ts boot -i || echo "(none)"
  # EPERM is the errno docker's default seccomp profile returns for a blocked syscall.
  # nginx daemonizes here, so its master writes the pid file and the shell can read it.
  echo "nginx with the default seccomp profile, then with seccomp unconfined:"
  docker run --rm "$image" sh -c 'nginx && sleep 1 && echo "started, pid $(cat /run/nginx.pid)"' || true
  docker run --rm --security-opt seccomp=unconfined "$image" \
    sh -c 'nginx && sleep 1 && echo "started, pid $(cat /run/nginx.pid)"' || true
  exit 1
fi
docker rm -f "$name"
