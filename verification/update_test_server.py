"""1.1.1 sandbox stand-in for the GitHub releases page (tests only, never shipped).

Usage: python3 update_test_server.py <config.json>
Prints "PORT <n>" once listening on 127.0.0.1. The config file is read again on every
request, so a test can change the behaviour between steps:

  {"latest": {...GitHub release JSON; "{base}" in strings is replaced by http://127.0.0.1:<port>...},
   "files": "<folder with the downloads>",
   "api_status": 200, "api_delay": 0,
   "drop_once": ["file name", ...],   # first download of it stops half way (connection closed)
   "drop_always": ["file name", ...],
   "redirect": true,                  # /download/<f> answers 302 to /objects/<f>, as GitHub does
   "file_delay": 0}
Writes every request line to <config>.log.
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG = sys.argv[1]
DROPPED = set()


def config():
    with open(CONFIG) as f:
        return json.load(f)


def note(text):
    with open(CONFIG + ".log", "a") as f:
        f.write(text + "\n")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        cfg = config()
        base = "http://127.0.0.1:%d" % self.server.server_port
        note("GET %s range=%s ua=%s" % (self.path, self.headers.get("Range", ""), self.headers.get("User-Agent", "")))
        if self.path.startswith("/api/latest"):
            time.sleep(float(cfg.get("api_delay", 0)))
            status = int(cfg.get("api_status", 200))
            body = json.dumps(cfg.get("latest", {})).replace("{base}", base).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/download/") and cfg.get("redirect", True):
            name = self.path.split("/download/", 1)[1]
            self.send_response(302)
            self.send_header("Location", base + "/objects/" + name)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path.startswith("/download/") or self.path.startswith("/objects/"):
            name = self.path.rsplit("/", 1)[1]
            path = os.path.join(cfg["files"], name)
            if not os.path.isfile(path):
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            data = open(path, "rb").read()
            start = 0
            rng = self.headers.get("Range", "")
            if rng.startswith("bytes="):
                start = int(rng[6:].split("-")[0])
            if start >= len(data) and start > 0:
                self.send_response(416)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            part = data[start:]
            self.send_response(206 if start > 0 else 200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(part)))
            if start > 0:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(data) - 1, len(data)))
            self.end_headers()
            drop = name in cfg.get("drop_always", []) or (name in cfg.get("drop_once", []) and name not in DROPPED)
            delay = float(cfg.get("file_delay", 0))
            sent = 0
            step = 65536
            try:
                while sent < len(part):
                    if drop and sent >= len(part) // 2:
                        DROPPED.add(name)
                        note("DROP %s at %d" % (name, start + sent))
                        self.close_connection = True
                        self.connection.shutdown(2)
                        return
                    self.wfile.write(part[sent:sent + step])
                    sent += step
                    if delay:
                        time.sleep(delay)
            except (BrokenPipeError, ConnectionResetError, OSError):
                return
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print("PORT %d" % server.server_port, flush=True)
with open(CONFIG + ".port", "w") as f:
    f.write(str(server.server_port))
server.serve_forever()
