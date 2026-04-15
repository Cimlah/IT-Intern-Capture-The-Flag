"""Tiny auth-gated JSON API for task 08.

Routes:
  GET /           -> list of endpoints
  GET /status     -> public; fake metrics
  GET /items      -> public; fake inventory
  GET /vault      -> requires X-Auth-Token == FLAG_TASK08_AUTH_TOKEN;
                     returns {"secret": FLAG_TASK08_SECRET}
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

AUTH_TOKEN = os.environ["FLAG_TASK08_AUTH_TOKEN"]
SECRET = os.environ["FLAG_TASK08_SECRET"]

ROUTES = {
    "/": {"endpoints": ["/", "/status", "/items", "/vault"]},
    "/status": {"uptime_s": 4242, "requests_total": 12345, "errors_total": 3},
    "/items": {"items": [
        {"id": 1, "name": "wrench"},
        {"id": 2, "name": "hammer"},
        {"id": 3, "name": "screwdriver"},
    ]},
}


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/vault":
            token = self.headers.get("X-Auth-Token", "")
            if token != AUTH_TOKEN:
                self._send_json(401, {"error": "missing or invalid X-Auth-Token"})
                return
            self._send_json(200, {"secret": SECRET})
            return
        if path in ROUTES:
            self._send_json(200, ROUTES[path])
            return
        self._send_json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        # quieter default logs
        print("jupiter-api: " + (fmt % args))


def main():
    srv = HTTPServer(("0.0.0.0", 8080), Handler)
    print("task08-api: listening on :8080")
    srv.serve_forever()


if __name__ == "__main__":
    main()
