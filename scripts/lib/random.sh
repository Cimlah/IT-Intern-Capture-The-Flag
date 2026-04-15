#!/usr/bin/env bash
# Random-value helpers used by generate-flags.sh.
# Source this file; it exports no state besides defining functions.

set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORDLIST="${WORDLIST:-$_LIB_DIR/wordlist.txt}"

rand_hex() {
  local n="${1:-8}"
  local bytes=$(( (n + 1) / 2 ))
  local out
  out="$(openssl rand -hex "$bytes")"
  printf '%s' "${out:0:$n}"
}

rand_digits() {
  local n="${1:-4}"
  local out=""
  while [ "${#out}" -lt "$n" ]; do
    out="${out}$((RANDOM % 10))"
  done
  printf '%s' "${out:0:$n}"
}

rand_word() {
  local lines
  lines=$(wc -l <"$WORDLIST")
  local idx=$(( (RANDOM * 32768 + RANDOM) % lines + 1 ))
  sed -n "${idx}p" "$WORDLIST"
}

rand_triple() {
  printf '%s-%s-%s' "$(rand_word)" "$(rand_word)" "$(rand_word)"
}

rand_pronounceable() {
  printf '%s-%s' "$(rand_word)" "$(rand_digits 4)"
}

rand_port() {
  local lo="${1:-1024}"
  local hi="${2:-65000}"
  local span=$(( hi - lo + 1 ))
  local r=$(( (RANDOM * 32768 + RANDOM) % span + lo ))
  echo "$r"
}

rand_sentence() {
  printf '%s %s %s %s' "$(rand_word)" "$(rand_word)" "$(rand_word)" "$(rand_word)"
}

sha256_hex() {
  printf '%s' "$1" | openssl dgst -sha256 -r | awk '{print $1}'
}

b64_encode() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

xor_hex() {
  local a_hex="$1" b_hex="$2"
  python3 - "$a_hex" "$b_hex" <<'PY'
import sys
a = bytes.fromhex(sys.argv[1])
b = bytes.fromhex(sys.argv[2])
out = bytes(x ^ y for x, y in zip(a, b))
sys.stdout.write(out.hex())
PY
}

ascii_to_hex() {
  printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}
