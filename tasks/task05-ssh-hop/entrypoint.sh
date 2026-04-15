#!/usr/bin/env bash
# SSH hop host for task 05. Intern logs in as `pivot`, reads /home/pivot/flag.txt.
set -euo pipefail

: "${FLAG_TASK05_SSH_PASS:?missing FLAG_TASK05_SSH_PASS}"
: "${FLAG_TASK05_FILE:?missing FLAG_TASK05_FILE}"

# Create/refresh the pivot user
if ! id -u pivot >/dev/null 2>&1; then
  adduser -D -h /home/pivot -s /bin/sh pivot
fi
echo "pivot:${FLAG_TASK05_SSH_PASS}" | chpasswd

install -d -o pivot -g pivot -m 0755 /home/pivot
printf '%s\n' "${FLAG_TASK05_FILE}" > /home/pivot/flag.txt
chown pivot:pivot /home/pivot/flag.txt
chmod 0644 /home/pivot/flag.txt

# Host keys (generated in the image, but regenerate if missing)
ssh-keygen -A

mkdir -p /var/run/sshd
echo "task05-ssh-hop: sshd starting; pivot home is /home/pivot"
exec /usr/sbin/sshd -D -e
