#!/usr/bin/env bash
# Recreate the engine workspace from the public forks. Idempotent.
# Does NOT run `gclient sync` (tens of GB); see sync.sh.
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$ENGINE_WS"; cd "$ENGINE_WS"

[ -d depot_tools ] || git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android >/dev/null

# 1. Flutter (framework + engine), branch ota/stable.
[ -d "$FLUTTER_SRC/.git" ] || git clone --branch "$FORK_BRANCH" "$FORK_MIRROR" "$FLUTTER_SRC"
git -C "$FLUTTER_SRC" checkout -q "$FORK_BRANCH"
# engine.version = HEAD, as an UNCOMMITTED working-tree edit: the engine build
# stamps `git rev-parse HEAD` into its artifacts (Maven POM 1.0.0-<hash>) while
# flutter_tools reads this file, and a committed file cannot hold its own hash.
git -C "$FLUTTER_SRC" rev-parse HEAD > "$FLUTTER_SRC/bin/internal/engine.version"
cp "$SELFHOST_REPO/engine/gclient.template" "$FLUTTER_SRC/.gclient"

# 2. Updater (for the standalone patch tool).
[ -d "$UPDATER_SRC/.git" ] || git clone --branch "$UPDATER_BRANCH" "$UPDATER_MIRROR" "$UPDATER_SRC"
git -C "$UPDATER_SRC" checkout -q "$UPDATER_BRANCH"

echo "workspace ready: engine $(engine_commit)"
echo "next: engine/scripts/sync.sh, build_host.sh, build_android.sh {arm64,arm,x64}, build_patch_tool.sh, make_mirror.sh"
