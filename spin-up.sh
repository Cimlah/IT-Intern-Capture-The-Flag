#!/usr/bin/env bash
# Multi-instance CTF spinup: generate flags, build images, bring up an isolated
# stack, print connection info + mentor password.
#
# Usage: ./spin-up.sh [<instance-name>] [--fresh]
#
# Each named instance is a separate Compose project (COMPOSE_PROJECT_NAME=
# ctf-<name>) with its own Docker network, its own secrets under
# secrets/<name>/, and its own host SSH port (auto-allocated if not set).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

INSTANCE="default"
FRESH=0

for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [<instance-name>] [--fresh]

Arguments:
  <instance-name>   short name (default: "default"); scopes the Compose project,
                    the network, the secrets dir, and the host SSH port.
  --fresh           regenerate all flags even if secrets/<name>/hub.env exists

Environment:
  CTF_SSH_PORT         force a specific host SSH port (default: first free port
                       >= 2222)
  CTF_MENTOR_PASSWORD  override the generated mentor password
  CTF_ALLOW_RESET      if set to 1, enables in-Ink reset key
EOF
      exit 0
      ;;
    --*) : ;;  # other flags — ignored here
    *)
      # First non-flag positional arg is the instance name
      if [ "$INSTANCE" = "default" ]; then
        INSTANCE="$arg"
      fi
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

SECRETS_DIR="$REPO_ROOT/secrets/$INSTANCE"
OVERRIDE_FILE="$SECRETS_DIR/override.yml"
export COMPOSE_PROJECT_NAME="ctf-$INSTANCE"
export CTF_SECRETS_DIR="$SECRETS_DIR"

_need_gen=1
if [ -f "$SECRETS_DIR/hub.env" ] && [ "$FRESH" -eq 0 ]; then
  echo "==> secrets/$INSTANCE/hub.env already exists; reusing (pass --fresh to regenerate)"
  _need_gen=0
fi

MENTOR_PASSWORD=""
if [ "$_need_gen" -eq 1 ]; then
  echo "==> generating flags for instance '$INSTANCE'..."
  _gen_output="$(bash scripts/generate-flags.sh "$SECRETS_DIR")"
  MENTOR_PASSWORD="$(printf '%s' "$_gen_output" | sed -n 's/^MENTOR_PASSWORD=//p')"
fi

# Port allocation: honor CTF_SSH_PORT if set, otherwise pick the lowest free
# port >= 2222. ss is preferred; fall back to bash /dev/tcp probing.
if [ -z "${CTF_SSH_PORT:-}" ]; then
  _port=2222
  _port_is_free() {
    if command -v ss >/dev/null 2>&1; then
      ! ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN
    else
      ! (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null
    fi
  }
  while ! _port_is_free "$_port"; do
    _port=$(( _port + 1 ))
    if [ "$_port" -gt 9999 ]; then
      echo "ERROR: no free port found in 2222-9999 range" >&2
      exit 1
    fi
  done
  CTF_SSH_PORT="$_port"
fi
export CTF_SSH_PORT

# Persist instance metadata so tear-down + smoke-test can find it
cat > "$SECRETS_DIR/.instance.env" <<EOF
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
CTF_SSH_PORT=$CTF_SSH_PORT
CTF_SECRETS_DIR=$SECRETS_DIR
EOF
chmod 600 "$SECRETS_DIR/.instance.env"

COMPOSE_FILES=(-f docker-compose.yml -f "$OVERRIDE_FILE")

echo "==> docker compose build (project=$COMPOSE_PROJECT_NAME)"
docker compose "${COMPOSE_FILES[@]}" build

echo "==> docker compose up -d"
docker compose "${COMPOSE_FILES[@]}" up -d --remove-orphans

echo "==> waiting for services to report running..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if docker compose "${COMPOSE_FILES[@]}" ps --format json 2>/dev/null | grep -q '"State":"running"'; then
    break
  fi
  sleep 1
done

cat <<EOF

=============================================================
 CTF instance '$INSTANCE' is up.

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
 Tear down with: ./tear-down.sh $INSTANCE
 Smoke test:     ./smoke-test.sh $INSTANCE
=============================================================
EOF
