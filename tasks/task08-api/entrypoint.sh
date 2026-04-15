#!/usr/bin/env sh
set -eu
: "${FLAG_TASK08_AUTH_TOKEN:?missing FLAG_TASK08_AUTH_TOKEN}"
: "${FLAG_TASK08_SECRET:?missing FLAG_TASK08_SECRET}"
exec python3 /srv/app.py
