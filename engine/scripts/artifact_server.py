#!/usr/bin/env python3
# Copyright 2026 the OTA authors. All rights reserved.
"""Our own artifact server for the self-built Flutter engine.

Serves the Flutter tool, the Gradle plugin and the ota CLI from OTA's own
builds (in place of Shorebird's download host). It is also a fence: every request
is logged, and anything we did not build is refused unless a rule explicitly
allows it.

For each GET/HEAD the first matching rule wins:
  SERVE        file exists under --root at the request path (our build output)
  PLACEHOLDER  path matches a regex in --placeholders; serves a zip holding only
               OTA_PLACEHOLDER.txt (the tool's unzip rejects an empty zip).
               Only for artifacts the tool downloads but never uses for an
               Android release build (each regex carries its reason).
  GOOGLE       path matches a regex in --google-allow; proxied to
               https://storage.googleapis.com (engine-independent assets
               published by Google, e.g. Material fonts, Gradle wrapper).
  MISS         everything else: 404.

Log format (tab separated): time, method, action, status, bytes, path.
Stdlib only.
"""
import argparse
import http.server
import io
import os
import re
import shutil
import sys
import threading
import time
import urllib.error
import urllib.request
import zipfile


def _placeholder_zip():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        info = zipfile.ZipInfo("OTA_PLACEHOLDER.txt", date_time=(2026, 1, 1, 0, 0, 0))
        info.external_attr = 0o644 << 16
        z.writestr(info, "OTA's release-only toolchain does not build this artifact;\n"
                         "Android release builds never read it. See docs/cleanroom.md T1-17\n"
                         "and engine/mirror_placeholders.txt.\n")
    return buf.getvalue()


PLACEHOLDER_ZIP = _placeholder_zip()
GOOGLE = "https://storage.googleapis.com"


def load_rules(path):
    rules = []
    if path and os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    rules.append(re.compile(line))
    return rules


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "ota-artifacts/1"
    root = "."
    placeholders = []
    google_allow = []
    log_lock = threading.Lock()
    log_path = None

    def log_message(self, fmt, *args):  # silence default stderr logging
        pass

    def record(self, action, status, nbytes):
        line = "\t".join([
            time.strftime("%Y-%m-%dT%H:%M:%S"), self.command, action,
            str(status), str(nbytes), self.path,
        ])
        with self.log_lock:
            print(line, flush=True)
            if self.log_path:
                with open(self.log_path, "a") as f:
                    f.write(line + "\n")

    def do_HEAD(self):
        self.handle_request(head=True)

    def do_GET(self):
        self.handle_request(head=False)

    def send_bytes(self, data, content_type="application/octet-stream",
                   head=False):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if not head:
            self.wfile.write(data)

    def handle_request(self, head):
        path = self.path.split("?", 1)[0]
        rel = os.path.normpath(path.lstrip("/"))
        if rel.startswith(".."):
            self.send_error(400)
            self.record("BAD", 400, 0)
            return
        local = os.path.join(self.root, rel)
        if os.path.isfile(local):
            size = os.path.getsize(local)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(size))
            self.end_headers()
            if not head:
                with open(local, "rb") as f:
                    shutil.copyfileobj(f, self.wfile)
            self.record("SERVE", 200, size)
            return
        if any(r.search(path) for r in self.placeholders):
            self.send_bytes(PLACEHOLDER_ZIP, "application/zip", head)
            self.record("PLACEHOLDER", 200, len(PLACEHOLDER_ZIP))
            return
        if any(r.search(path) for r in self.google_allow):
            self.proxy_google(path, head)
            return
        self.send_error(404, "not built by us")
        self.record("MISS", 404, 0)

    def proxy_google(self, path, head):
        req = urllib.request.Request(GOOGLE + path,
                                     method="HEAD" if head else "GET")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                self.send_response(resp.status)
                length = resp.headers.get("Content-Length")
                self.send_header("Content-Type", resp.headers.get(
                    "Content-Type", "application/octet-stream"))
                if length:
                    self.send_header("Content-Length", length)
                self.end_headers()
                n = 0
                if not head:
                    while True:
                        chunk = resp.read(1 << 16)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        n += len(chunk)
                self.record("GOOGLE", resp.status, n)
        except urllib.error.HTTPError as e:
            self.send_error(e.code)
            self.record("GOOGLE", e.code, 0)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.environ.get("MIRROR_DIR"))
    ap.add_argument("--port", type=int,
                    default=int(os.environ.get("ARTIFACT_PORT", "8099")))
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--log")
    ap.add_argument("--placeholders",
                    default=os.path.join(here, "..", "mirror_placeholders.txt"))
    ap.add_argument("--google-allow",
                    default=os.path.join(here, "..", "mirror_google_allow.txt"))
    args = ap.parse_args()
    if not args.root or not os.path.isdir(args.root):
        sys.exit(f"--root {args.root!r} is not a directory")
    Handler.root = os.path.abspath(args.root)
    Handler.placeholders = load_rules(args.placeholders)
    Handler.google_allow = load_rules(args.google_allow)
    Handler.log_path = args.log
    srv = http.server.ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"serving {Handler.root} on http://{args.bind}:{args.port} "
          f"({len(Handler.placeholders)} placeholder rules, "
          f"{len(Handler.google_allow)} google rules)", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
