#!/usr/bin/env bash
# Tear down the CTF stack. By default wipes the state volume AND regenerated
# secrets. Pass --keep-state to preserve intern progress, --keep-secrets to
# preserve flag files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

KEEP_STATE=0
KEEP_SECRETS=0
YES=0
for arg in "$@"; do
  case "$arg" in
    --keep-state) KEEP_STATE=1 ;;
    --keep-secrets) KEEP_SECRETS=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--keep-state] [--keep-secrets] [--yes]

  --keep-state     preserve the intern-progress docker volume
  --keep-secrets   preserve secrets/*.env + secrets/mentor.hash
  -y, --yes        no confirmation prompt
EOF
      exit 0
      ;;
  esac
done

if [ "$YES" -eq 0 ]; then
  printf 'This will stop and remove all CTF containers. Continue? [y/N] '
  read -r ans
  case "$ans" in
    y|Y|yes|YES) : ;;
    *) echo "aborted"; exit 1 ;;
  esac
fi

if [ "$KEEP_STATE" -eq 1 ]; then
  echo "==> docker compose down (keeping volumes)"
  docker compose down
else
  echo "==> docker compose down -v"
  docker compose down -v
fi

if [ "$KEEP_SECRETS" -eq 0 ]; then
  echo "==> clearing secrets/"
  find secrets -maxdepth 1 -type f \( -name '*.env' -o -name '*.hash' \) -delete
  if [ -f docker-compose.override.yml ]; then
    echo "==> removing docker-compose.override.yml"
    rm -f docker-compose.override.yml
  fi
fi

echo "==> tear-down complete"
