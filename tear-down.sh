#!/usr/bin/env bash
# Tear down one or all CTF instances.
#
# Usage: ./tear-down.sh [<instance-name>|--all] [--keep-state] [--keep-secrets] [-y]
#
# Each instance is a separate Compose project; scoping the teardown to one
# instance leaves the others running.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

INSTANCE=""
ALL=0
KEEP_STATE=0
KEEP_SECRETS=0
YES=0
for arg in "$@"; do
  case "$arg" in
    --all) ALL=1 ;;
    --keep-state) KEEP_STATE=1 ;;
    --keep-secrets) KEEP_SECRETS=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [<instance-name>|--all] [--keep-state] [--keep-secrets] [-y]

Arguments:
  <instance-name>   tear down only this instance (default: "default")
  --all             tear down every instance found under secrets/

Flags:
  --keep-state      preserve the intern-progress docker volume
  --keep-secrets    preserve secrets/<name>/*.env + mentor.hash + override.yml
  -y, --yes         skip the confirmation prompt
EOF
      exit 0
      ;;
    --*) : ;;
    *)
      if [ -z "$INSTANCE" ]; then
        INSTANCE="$arg"
      fi
      ;;
  esac
done

if [ "$ALL" -eq 0 ] && [ -z "$INSTANCE" ]; then
  INSTANCE="default"
fi

_teardown_one() {
  local name="$1"
  local secrets_dir="$REPO_ROOT/secrets/$name"
  local override="$secrets_dir/override.yml"
  local project="ctf-$name"

  if [ -f "$secrets_dir/.instance.env" ]; then
    # shellcheck disable=SC1090
    . "$secrets_dir/.instance.env"
    project="${COMPOSE_PROJECT_NAME:-$project}"
  fi

  export COMPOSE_PROJECT_NAME="$project"
  export CTF_SECRETS_DIR="$secrets_dir"
  # CTF_SSH_PORT isn't strictly required by `down`, but the compose file's
  # `${CTF_SSH_PORT:-2222}` substitution still needs a value during parse.
  export CTF_SSH_PORT="${CTF_SSH_PORT:-2222}"

  local compose_args=(-f docker-compose.yml)
  if [ -f "$override" ]; then
    compose_args+=(-f "$override")
  fi

  if [ "$KEEP_STATE" -eq 1 ]; then
    echo "==> [$name] docker compose down (keeping volumes)"
    docker compose "${compose_args[@]}" down || true
  else
    echo "==> [$name] docker compose down -v"
    docker compose "${compose_args[@]}" down -v || true
  fi

  if [ "$KEEP_SECRETS" -eq 0 ] && [ -d "$secrets_dir" ]; then
    echo "==> [$name] clearing $secrets_dir"
    rm -rf "$secrets_dir"
  fi
}

_confirm() {
  if [ "$YES" -eq 1 ]; then return 0; fi
  printf '%s Continue? [y/N] ' "$1"
  read -r ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) echo "aborted"; exit 1 ;;
  esac
}

if [ "$ALL" -eq 1 ]; then
  _instances=()
  if [ -d "$REPO_ROOT/secrets" ]; then
    for d in "$REPO_ROOT"/secrets/*/; do
      [ -d "$d" ] || continue
      _instances+=("$(basename "$d")")
    done
  fi
  if [ "${#_instances[@]}" -eq 0 ]; then
    echo "==> no instances found under secrets/"
    exit 0
  fi
  _confirm "This will tear down ${#_instances[@]} instance(s): ${_instances[*]}."
  for _n in "${_instances[@]}"; do
    _teardown_one "$_n"
  done
else
  _confirm "This will tear down instance '$INSTANCE'."
  _teardown_one "$INSTANCE"
fi

echo "==> tear-down complete"
