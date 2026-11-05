#!/usr/bin/env bash
# Run our artifact server in the foreground, logging to $ENGINE_WS/artifact_server.log
set -euo pipefail
source "$(dirname "$0")/env.sh"
exec python3 "$(dirname "$0")/artifact_server.py" --root "$MIRROR_DIR" \
  --port "$ARTIFACT_PORT" --log "$ENGINE_WS/artifact_server.log" "$@"
