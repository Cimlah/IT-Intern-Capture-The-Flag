#!/usr/bin/env bash
# Serves internal.ctf DNS zone via dnsmasq with a single TXT record that the
# intern must look up for task 06.
set -euo pipefail

: "${FLAG_TASK06_HOST:?missing FLAG_TASK06_HOST}"
: "${FLAG_TASK06_TXT:?missing FLAG_TASK06_TXT}"

cat > /etc/dnsmasq.conf <<EOF
no-resolv
no-hosts
log-queries
port=53
domain-needed
bogus-priv
local=/internal.ctf/
address=/${FLAG_TASK06_HOST}/10.42.0.99
txt-record=${FLAG_TASK06_HOST},${FLAG_TASK06_TXT}
EOF

echo "task06-dns: serving TXT ${FLAG_TASK06_HOST}"
exec dnsmasq -k --log-facility=- --conf-file=/etc/dnsmasq.conf
