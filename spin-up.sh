#!/usr/bin/env bash
# One-click CTF spinup: generate flags, build images, bring up the stack,
# print connection info + mentor password.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SECRETS_DIR="$REPO_ROOT/secrets"
CTF_SSH_PORT="${CTF_SSH_PORT:-2222}"
FRESH=0

for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--fresh]

  --fresh    regenerate all flags even if secrets/ already exists

Environment:
  CTF_SSH_PORT         host port mapped to hub sshd (default 2222)
  CTF_MENTOR_PASSWORD  override the generated mentor password
  CTF_ALLOW_RESET      if set to 1, enables in-Ink reset key
EOF
      exit 0
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not on PATH." >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin is required." >&2
  exit 1
fi

cd "$REPO_ROOT"

_need_gen=1
if [ -f "$SECRETS_DIR/hub.env" ] && [ "$FRESH" -eq 0 ]; then
  echo "==> secrets/hub.env already exists; reusing (pass --fresh to regenerate)"
  _need_gen=0
fi

MENTOR_PASSWORD=""
if [ "$_need_gen" -eq 1 ]; then
  echo "==> generating per-instance flags..."
  _gen_output="$(bash scripts/generate-flags.sh)"
  MENTOR_PASSWORD="$(printf '%s' "$_gen_output" | sed -n 's/^MENTOR_PASSWORD=//p')"
else
  echo "==> (mentor password is from the previous spinup; not shown)"
fi

echo "==> docker compose build"
CTF_SSH_PORT="$CTF_SSH_PORT" docker compose build

echo "==> docker compose up -d"
# --remove-orphans cleans up decoys from the previous run whose names are no
# longer in docker-compose.override.yml (the override is regenerated with a
# fresh random set each spin-up).
CTF_SSH_PORT="$CTF_SSH_PORT" docker compose up -d --remove-orphans

echo "==> waiting for services to report running..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if docker compose ps --format json 2>/dev/null | grep -q '"State":"running"'; then
    break
  fi
  sleep 1
done

cat <<EOF

=============================================================
 CTF instance is up.

 SSH to the hub:
   ssh -t intern@localhost -p ${CTF_SSH_PORT}
   password: ctf

EOF

if [ -n "$MENTOR_PASSWORD" ]; then
  cat <<EOF
 Mentor password (shown ONCE — save it now):
   ${MENTOR_PASSWORD}

 Use \`ctf-reveal\` from inside the hub to display all answers.

EOF
fi

cat <<EOF
 Tear down with: ./tear-down.sh
 Smoke test:     ./smoke-test.sh
=============================================================
EOF
