#!/usr/bin/env bash
# Hub container entrypoint: generate host keys on first boot, fix up file
# permissions on the bind-mounted answer store, and start sshd in foreground.
set -euo pipefail

# Generate SSH host keys if missing (happens on first run of a new instance)
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''
fi
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -q -t rsa -b 3072 -f /etc/ssh/ssh_host_rsa_key -N ''
fi

# Copy the bind-mounted answer store into a real root-owned file.
# Docker Desktop macOS/Windows bind mounts ignore in-container chmod/chown,
# so we cannot just `chmod 0600` the mounted file. Instead the compose file
# mounts the source at /etc/ctf/hub.env.src and we install it here with
# correct owner + mode. The setuid helpers read the copy (/etc/ctf/hub.env).
if [ -f /etc/ctf/hub.env.src ]; then
  install -m 0600 -o root -g root /etc/ctf/hub.env.src /etc/ctf/hub.env
else
  echo "entrypoint: FATAL — /etc/ctf/hub.env.src not mounted" >&2
  exit 1
fi
if [ -f /etc/ctf/mentor.hash.src ]; then
  install -m 0644 -o root -g root /etc/ctf/mentor.hash.src /etc/ctf/mentor.hash
else
  echo "entrypoint: FATAL — /etc/ctf/mentor.hash.src not mounted" >&2
  exit 1
fi

# Make sure the state directory is writable by the intern
install -d -o intern -g intern -m 0755 /var/ctf/state

# Ensure intern's home has a solutions/ dir for task 04 write-ups
install -d -o intern -g intern -m 0755 /home/intern/solutions

# Point the hub at task06-dns for the internal.ctf zone. Subnets are
# auto-allocated by Docker per instance, so we can't hardcode an IP — resolve
# the `venus` alias via Docker's embedded DNS (127.0.0.11) and prepend that IP
# to /etc/resolv.conf so `dig TXT foo.internal.ctf` hits dnsmasq first.
_dns_ip=""
for _i in 1 2 3 4 5; do
  _dns_ip=$(getent hosts venus 2>/dev/null | awk '{print $1; exit}')
  [ -n "$_dns_ip" ] && break
  sleep 0.5
done
if [ -n "$_dns_ip" ] && ! grep -q "nameserver $_dns_ip" /etc/resolv.conf 2>/dev/null; then
  printf 'nameserver %s\n%s\n' "$_dns_ip" "$(cat /etc/resolv.conf 2>/dev/null || true)" > /etc/resolv.conf.new 2>/dev/null || true
  mv /etc/resolv.conf.new /etc/resolv.conf 2>/dev/null || true
fi

mkdir -p /run/sshd
exec /usr/sbin/sshd -D -e
