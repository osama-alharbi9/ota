#!/usr/bin/env bash
# Point everything at the Mac's current LAN IP (run after changing networks).
# Updates PUBLIC_URL in .env and base_url in examples/flutter/ota.yaml, then
# recreates the api container. Apps released with the old URL must be
# re-released: base_url is baked into the app at build time.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IP="${1:-$(ipconfig getifaddr en0)}"
URL="http://$IP:8080"
sed -i '' -E "s#^PUBLIC_URL=.*#PUBLIC_URL=$URL#" "$ROOT/.env"
[ -f "$ROOT/examples/flutter/ota.yaml" ] && sed -i "" -E "s#^base_url: .*#base_url: $URL#" "$ROOT/examples/flutter/ota.yaml"
(cd "$ROOT" && docker compose up -d api >/dev/null)
for _ in $(seq 1 30); do curl -fsS -m 2 "$URL/healthz" >/dev/null 2>&1 && { echo "server healthy at $URL"; exit 0; }; sleep 1; done
echo "server not reachable at $URL"; exit 1
