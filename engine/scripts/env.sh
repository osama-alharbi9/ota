#!/usr/bin/env bash
# Shared settings for the self-built engine toolchain. Source, do not run.
# Every pin below is a PUBLIC revision; see docs/cleanroom.md for where each came from.

export ENGINE_WS="${ENGINE_WS:-$HOME/engine-src}"
export FLUTTER_SRC="$ENGINE_WS/flutter"          # monorepo: framework + engine/src
export ENGINE_SRC="$FLUTTER_SRC/engine/src"
export UPDATER_SRC="$ENGINE_WS/updater"          # public updater (patch tool)
export MIRROR_DIR="$ENGINE_WS/mirror"            # files our artifact server serves

# The public forks. Their branches carry our changes on top of the upstream pins below.
export FORK_MIRROR="${FORK_MIRROR:-https://github.com/osama-alharbi9/ota-flutter.git}"
export UPDATER_MIRROR="${UPDATER_MIRROR:-https://github.com/osama-alharbi9/ota-updater.git}"

# Upstream pins (public), used only when rebuilding the mirrors from scratch.
export FORK_URL="https://github.com/shorebirdtech/flutter.git"
export FORK_REV="c2c56ab2d5483bdf86152725342f55ca6faed946"   # CLI 1.6.93 bin/internal/flutter.version
export DART_URL="https://dart.googlesource.com/sdk.git"
export DART_REV="c70f78e7d682c158c15ca0c26c729b3ccb932284"   # fork DEPS 'dart_revision' = Dart 3.11.5 stable
export UPDATER_URL="https://github.com/shorebirdtech/updater.git"
export UPDATER_REV="185280e04828e7c828cd6a63a1c53b40b1ee509c" # fork DEPS 'updater_rev'

# Local branches that carry our patch series.
# Two refs, the way upstream Flutter rolls its engine (CLEANROOM T1-15):
#   ENGINE_BRANCH  the engine source commit that gets built; artifacts are keyed by its hash
#   FORK_BRANCH    ENGINE_BRANCH + one commit writing that hash to bin/internal/engine.version;
#                  this is what the ota CLI checks out (bin/internal/flutter.version)
export ENGINE_BRANCH="ota/engine"
export FORK_BRANCH="ota/stable"
export UPDATER_BRANCH="ota/stable"

# Artifact server (engine/scripts/artifact_server.py).
export ARTIFACT_PORT="${ARTIFACT_PORT:-8099}"
export ARTIFACT_URL="${OTA_ARTIFACTS_URL:-http://127.0.0.1:$ARTIFACT_PORT}"

# Build parallelism. 24 GB RAM: keep linking from swapping.
export JOBS="${JOBS:-6}"

export PATH="$ENGINE_WS/depot_tools:$PATH"
# Use the ninja the checkout pins (DEPS 'third_party/ninja', CIPD), not
# depot_tools' wrapper, which needs a bootstrap we skip with DEPOT_TOOLS_UPDATE=0.
export NINJA="$FLUTTER_SRC/third_party/ninja/ninja"
export DEPOT_TOOLS_UPDATE=0      # do not let depot_tools self-update mid-build
export DEPOT_TOOLS_METRICS=0

SELFHOST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SELFHOST_REPO
# Artifacts are keyed by the engine source commit. Builds run with HEAD at
# ENGINE_BRANCH and engine.version = HEAD as an uncommitted edit (the build
# stamps `git rev-parse HEAD` into artifacts, e.g. Maven POM 1.0.0-<hash>).
engine_commit() { git -C "$FLUTTER_SRC" rev-parse "$ENGINE_BRANCH"; }
framework_commit() { git -C "$FLUTTER_SRC" rev-parse "$FORK_BRANCH"; }
check_engine_version() {
  local want head have
  want=$(engine_commit); head=$(git -C "$FLUTTER_SRC" rev-parse HEAD)
  have=$(cat "$FLUTTER_SRC/bin/internal/engine.version")
  [ "$head" = "$want" ] || { echo "build from $ENGINE_BRANCH ($want); HEAD is $head (git checkout $ENGINE_BRANCH)"; return 1; }
  [ "$have" = "$want" ] || { echo "engine.version ($have) != $want; run: git -C $FLUTTER_SRC rev-parse HEAD > $FLUTTER_SRC/bin/internal/engine.version"; return 1; }
}
