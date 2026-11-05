#!/usr/bin/env bash
# Build the standalone `patch` packaging tool from the public updater repo.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$UPDATER_SRC/patch"
cargo build --release
ls -la "$UPDATER_SRC/target/release/patch"
shasum -a 256 "$UPDATER_SRC/target/release/patch"
