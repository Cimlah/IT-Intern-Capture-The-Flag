#!/usr/bin/env bash
# Serves the XOR ciphertext + key at /ct and /key as lowercase hex.
set -euo pipefail

: "${FLAG_TASK09_CIPHERTEXT:?missing FLAG_TASK09_CIPHERTEXT}"
: "${FLAG_TASK09_KEY:?missing FLAG_TASK09_KEY}"

mkdir -p /srv/www
printf '%s' "$FLAG_TASK09_CIPHERTEXT" > /srv/www/ct
printf '%s' "$FLAG_TASK09_KEY"        > /srv/www/key

echo "task09-crypto: serving ct + key on :80"
exec busybox-extras httpd -f -p 80 -h /srv/www
