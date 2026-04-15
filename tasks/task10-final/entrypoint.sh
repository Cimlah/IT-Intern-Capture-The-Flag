#!/usr/bin/env bash
# Serves the expected sha256 hash at /expected.sha256 so the intern can
# sanity-check their task-10 script output before submitting.
set -euo pipefail

: "${FLAG_TASK10_EXPECTED:?missing FLAG_TASK10_EXPECTED}"

mkdir -p /srv/www
printf '%s\n' "$FLAG_TASK10_EXPECTED" > /srv/www/expected.sha256

echo "task10-final: serving expected.sha256 on :80"
exec busybox-extras httpd -f -p 80 -h /srv/www
