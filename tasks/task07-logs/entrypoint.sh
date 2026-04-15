#!/usr/bin/env bash
# Generates a synthetic Apache access log with ~20k 200s and a single 500
# entry containing FLAG_TASK07_TX. Serves it over HTTP on :80.
set -euo pipefail

: "${FLAG_TASK07_TX:?missing FLAG_TASK07_TX}"

LOG=/srv/www/access.log
mkdir -p /srv/www

_base_date="2026-04-14T09:00:00Z"
echo "task07-logs: generating access.log..."

# Fast log generation via awk. A bash for-loop over 20k iterations takes
# several seconds and creates a race with httpd starting — this finishes
# in well under 100ms.
awk -v tx="$FLAG_TASK07_TX" -v base_date="$_base_date" '
BEGIN {
  srand();
  split("/index.html /about /contact /api/users /api/items /static/app.js /static/app.css /favicon.ico /img/logo.png /health", paths, " ");
  split("Mozilla/5.0 curl/7.88.1 Wget/1.21 Go-http-client/1.1 python-requests/2.31", agents, " ");
  np = 10; na = 5;

  # 20000 uneventful 200/304 requests
  for (i = 0; i < 20000; i++) {
    ip = int(rand()*223 + 1) "." int(rand()*256) "." int(rand()*256) "." int(rand()*256);
    status = (int(rand()*10) == 0) ? 304 : 200;
    size = int(rand()*9000) + 200;
    printf "%s - - [%s] \"GET %s HTTP/1.1\" %d %d \"-\" \"%s\"\n",
           ip, base_date, paths[int(rand()*np) + 1], status, size, agents[int(rand()*na) + 1];
  }

  # One 500 line with the transaction ID buried in the user-agent field
  ip = int(rand()*223 + 1) "." int(rand()*256) "." int(rand()*256) "." int(rand()*256);
  printf "%s - - [%s] \"POST /api/submit HTTP/1.1\" 500 512 \"-\" \"Mozilla/5.0 %s\"\n",
         ip, base_date, tx;

  # A few hundred more noise lines after the needle
  for (i = 0; i < 500; i++) {
    ip = int(rand()*223 + 1) "." int(rand()*256) "." int(rand()*256) "." int(rand()*256);
    size = int(rand()*9000) + 200;
    printf "%s - - [%s] \"GET %s HTTP/1.1\" 200 %d \"-\" \"%s\"\n",
           ip, base_date, paths[int(rand()*np) + 1], size, agents[int(rand()*na) + 1];
  }
}
' | shuf > "$LOG"

echo "task07-logs: access.log has $(wc -l <"$LOG") lines"
exec busybox-extras httpd -f -p 80 -h /srv/www
