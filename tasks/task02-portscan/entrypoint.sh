#!/usr/bin/env bash
# Serves two files over HTTP:
#   /             — base64(FLAG_TASK04_PLAINTEXT), answer for task 03
#   /hop.txt      — FLAG_TASK05_SSH_PASS, hint chain into task 05
#
# Binds to FLAG_TASK02_PORT.
set -euo pipefail

: "${FLAG_TASK02_PORT:?missing FLAG_TASK02_PORT}"
: "${FLAG_TASK04_PLAINTEXT:?missing FLAG_TASK04_PLAINTEXT}"
: "${FLAG_TASK05_SSH_PASS:?missing FLAG_TASK05_SSH_PASS}"

mkdir -p /srv/www
printf '%s' "$FLAG_TASK04_PLAINTEXT" | base64 | tr -d '\n' > /srv/www/index.html
printf '%s\n' "$FLAG_TASK05_SSH_PASS" > /srv/www/hop.txt

echo "task02-portscan: serving on port ${FLAG_TASK02_PORT}"
exec busybox-extras httpd -f -p "${FLAG_TASK02_PORT}" -h /srv/www
