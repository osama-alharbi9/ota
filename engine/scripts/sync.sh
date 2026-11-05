#!/usr/bin/env bash
# Fetch engine dependencies with gclient. Large download (roughly 20-30 GB).
set -euo pipefail
source "$(dirname "$0")/env.sh"
df -h "$ENGINE_WS" | tail -1
cd "$FLUTTER_SRC"
# --no-history: shallow dependency checkouts, saves several GB.
time gclient sync --no-history -j 8 "$@"
# third_party/updater comes from our mirror at DEPS updater_rev (ota/stable).
U="$ENGINE_SRC/flutter/third_party/updater"
git -C "$U" log --oneline -1
git -C "$U" remote get-url origin
# Record what the stock-Dart override actually resolved to.
git -C "$ENGINE_SRC/flutter/third_party/dart" log -1 --format='third_party/dart = %H %s'
git -C "$ENGINE_SRC/flutter/third_party/dart" remote get-url origin
df -h "$ENGINE_WS" | tail -1
