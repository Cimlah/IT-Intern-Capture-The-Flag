#!/usr/bin/env bash
# End-to-end smoke test. Run after ./spin-up.sh. Exits non-zero on any failure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
_pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

echo "== reading flags from secrets/hub.env"
if [ ! -f secrets/hub.env ]; then
  echo "ERROR: secrets/hub.env not found. Did you run ./spin-up.sh?" >&2
  exit 2
fi
# hub.env stores raw KEY=value lines (values may contain spaces, quotes, etc.).
# Parse it manually instead of `source`ing it — bash source would try to
# execute any value containing whitespace as a command.
while IFS= read -r _line || [ -n "$_line" ]; do
  case "$_line" in
    ''|\#*) continue ;;
  esac
  _k=${_line%%=*}
  _v=${_line#*=}
  case "$_k" in
    [A-Za-z_]*[A-Za-z0-9_]) export "$_k=$_v" ;;
  esac
done < secrets/hub.env

echo "== docker compose ps"
_running_count=$(docker compose ps --format json 2>/dev/null | grep -c '"State":"running"' || true)
if [ "$_running_count" -ge 10 ]; then
  _pass "at least 10 services running ($_running_count)"
else
  _fail "expected at least 10 running services, got $_running_count"
fi

echo "== hub can reach task containers"
_decoy_list=""
if [ -f secrets/decoys.env ]; then
  _decoy_list=$(grep '^DECOY_NAMES=' secrets/decoys.env | cut -d= -f2- | tr ',' ' ')
fi
for host in mercury mars-hop venus earth-logs jupiter-api saturn-crypto neptune-final $_decoy_list; do
  if docker compose exec -T hub getent hosts "$host" >/dev/null 2>&1; then
    _pass "hub resolves $host"
  else
    _fail "hub cannot resolve $host"
  fi
done

echo "== task02/03: HTTP on mercury:$FLAG_TASK02"
_body=$(docker compose exec -T hub curl -sf "http://mercury:${FLAG_TASK02}/" || true)
if [ "$_body" = "$FLAG_TASK03" ]; then
  _pass "mercury returns the expected base64"
else
  _fail "mercury returned: $_body (expected $FLAG_TASK03)"
fi

echo "== task04: plaintext matches base64 decode of task03"
_decoded=$(printf '%s' "$FLAG_TASK03" | base64 -d 2>/dev/null || true)
if [ "$_decoded" = "$FLAG_TASK04" ]; then
  _pass "base64 decode matches"
else
  _fail "base64 decode = '$_decoded', expected '$FLAG_TASK04'"
fi

echo "== task05: SSH hop into mars-hop as pivot"
_ssh_pass=$(grep '^FLAG_TASK05_SSH_PASS=' secrets/task05.env | cut -d= -f2-)
if docker compose exec -T hub sshpass -p "$_ssh_pass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null pivot@mars-hop cat /home/pivot/flag.txt 2>/dev/null | tr -d '\r\n' | grep -q "^${FLAG_TASK05}$"; then
  _pass "pivot flag file matches"
else
  # sshpass may not be installed — fall back to scripted expect via python
  _remote_flag=$(docker compose exec -T hub python3 - "$_ssh_pass" <<'PY' 2>/dev/null || true
import sys, pty, os, subprocess, time
pw = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("ssh", ["ssh", "-o", "StrictHostKeyChecking=no",
                      "-o", "UserKnownHostsFile=/dev/null",
                      "pivot@mars-hop", "cat /home/pivot/flag.txt"])
buf = b""
deadline = time.time() + 10
while time.time() < deadline:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    if b"password:" in buf.lower():
        os.write(fd, (pw + "\n").encode())
        buf = b""
# Print last line that looks like a flag
for line in buf.decode(errors="ignore").splitlines():
    line = line.strip()
    if line and "password" not in line.lower() and "warning" not in line.lower():
        print(line)
PY
)
  if printf '%s' "$_remote_flag" | grep -q "$FLAG_TASK05"; then
    _pass "pivot flag file matches (via python pty)"
  else
    _fail "pivot flag mismatch (saw: $_remote_flag)"
  fi
fi

echo "== task06: DNS TXT lookup"
_host=$(grep '^FLAG_TASK06_HOST=' secrets/hub.env | cut -d= -f2-)
_txt=$(docker compose exec -T hub dig @10.42.0.23 TXT "$_host" +short 2>/dev/null | tr -d '"' | tr -d '\r\n' | head -n1 || true)
if [ "$_txt" = "$FLAG_TASK06" ]; then
  _pass "dns TXT matches"
else
  _fail "dns TXT = '$_txt', expected '$FLAG_TASK06'"
fi

echo "== task07: log file contains the TX id"
# Fetch first, then grep. A direct `curl | grep -q` pipe is fragile under
# `set -o pipefail`: grep -q exits on first match, curl gets SIGPIPE while
# it still has ~1.5 MB of log left to stream, and pipefail reports the
# pipeline as failed even though the match succeeded.
_access_log=$(docker compose exec -T hub curl -sf http://earth-logs/access.log 2>/dev/null || true)
if [[ "$_access_log" == *"$FLAG_TASK07"* ]]; then
  _pass "access.log contains $FLAG_TASK07"
else
  _fail "access.log missing $FLAG_TASK07"
fi
unset _access_log

echo "== task08: authenticated API call"
_auth=$(grep '^FLAG_TASK08_AUTH_TOKEN=' secrets/task08.env | cut -d= -f2-)
_api=$(docker compose exec -T hub curl -sf -H "X-Auth-Token: $_auth" http://jupiter-api:8080/vault 2>/dev/null || true)
if printf '%s' "$_api" | grep -q "$FLAG_TASK08"; then
  _pass "api /vault returned the secret"
else
  _fail "api /vault returned: $_api"
fi

echo "== task09: XOR plaintext"
_ct=$(docker compose exec -T hub curl -sf http://saturn-crypto/ct 2>/dev/null || true)
_key=$(docker compose exec -T hub curl -sf http://saturn-crypto/key 2>/dev/null || true)
_xored=$(python3 - "$_ct" "$_key" <<'PY' 2>/dev/null || true
import sys
try:
    a = bytes.fromhex(sys.argv[1])
    b = bytes.fromhex(sys.argv[2])
    print(bytes(x ^ y for x, y in zip(a, b)).decode())
except Exception:
    pass
PY
)
if [ "$_xored" = "$FLAG_TASK09" ]; then
  _pass "xor plaintext matches"
else
  _fail "xor plaintext = '$_xored', expected '$FLAG_TASK09'"
fi

echo "== task10: expected.sha256 matches computed digest"
_expected_remote=$(docker compose exec -T hub curl -sf http://neptune-final/expected.sha256 2>/dev/null | tr -d '\r\n' || true)
_computed=$(python3 - "$FLAG_TASK01" "$FLAG_TASK02" "$FLAG_TASK03" "$FLAG_TASK04" "$FLAG_TASK05" "$FLAG_TASK06" "$FLAG_TASK07" "$FLAG_TASK08" "$FLAG_TASK09" <<'PY' 2>/dev/null || true
import hashlib, sys
joined = "\n".join(sys.argv[1:])
print(hashlib.sha256(joined.encode()).hexdigest())
PY
)
if [ "$_computed" = "$FLAG_TASK10" ] && [ "$_expected_remote" = "$FLAG_TASK10" ]; then
  _pass "task10 sha256 matches remote + computed"
else
  _fail "task10: remote=$_expected_remote, computed=$_computed, expected=$FLAG_TASK10"
fi

echo "== privilege separation: intern cannot read hub.env"
if docker compose exec -T -u intern hub sh -c 'cat /etc/ctf/hub.env >/dev/null 2>&1 && echo LEAK || echo OK' 2>/dev/null | grep -q OK; then
  _pass "intern cannot read /etc/ctf/hub.env"
else
  _fail "intern CAN read /etc/ctf/hub.env — privilege separation broken"
fi

echo "== ctf-verify helper rejects garbage"
if docker compose exec -T -u intern hub /usr/local/bin/ctf-verify task01 "definitely-wrong-$$" >/dev/null 2>&1; then
  _fail "ctf-verify accepted a wrong answer"
else
  _pass "ctf-verify rejects wrong answer"
fi

echo "== ctf-verify helper accepts correct answer"
if docker compose exec -T -u intern hub /usr/local/bin/ctf-verify task04 "$FLAG_TASK04" >/dev/null 2>&1; then
  _pass "ctf-verify accepts correct task04 answer"
else
  _fail "ctf-verify rejected the correct task04 answer"
fi

echo "== ink self-check"
if docker compose exec -T -u intern hub node /opt/ctf-hub/dist/index.js --self-check >/dev/null 2>&1; then
  _pass "ink --self-check"
else
  _fail "ink --self-check failed"
fi

printf '\n==> smoke test: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
