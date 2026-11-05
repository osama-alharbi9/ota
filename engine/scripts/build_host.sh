#!/usr/bin/env bash
# Build host (macOS arm64) release tools: Dart SDK from source, frontend_server,
# flutter_patched_sdk(_product), sky_engine, impellerc, font-subset, const_finder.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_engine_version
cd "$ENGINE_SRC"
./flutter/tools/gn --no-rbe --no-enable-unittests --runtime-mode=release \
  --mac-cpu=arm64 --no-prebuilt-dart-sdk
# default, plus the zips flutter_tools downloads from the artifact server. Upstream
# CI builds the same targets (ci/builders/{mac,linux}_host_engine.json,
# linux_android_debug_engine.json); make_mirror.sh maps them (CLEANROOM T1-17).
TARGETS=(default
  flutter/build/archives:flutter_patched_sdk    # zip_archives/flutter_patched_sdk_product.zip
  flutter/build/archives:artifacts              # zip_archives/darwin-arm64-release/artifacts.zip
  flutter/tools/font_subset)                    # zip_archives/darwin-arm64/font-subset.zip
# sky_engine.zip and flutter_gpu.zip are Android-only targets: build_android.sh arm64.
# dart-sdk-darwin-arm64.zip: flutter/build/archives:dart_sdk_archive fails for a Dart
# SDK built from source on macOS (it passes its entitlements file as an unrebased
# "//out/..." path; upstream's Mac CI uses a prebuilt SDK), so make_mirror.sh zips
# out/host_release_arm64/dart-sdk with upstream's build/zip.py instead.
[ $# -gt 0 ] || set -- "${TARGETS[@]}"
time "$NINJA" -C out/host_release_arm64 -j "$JOBS" "$@"
ls -d out/host_release_arm64/dart-sdk out/host_release_arm64/flutter_patched_sdk* \
      out/host_release_arm64/gen/dart-pkg/sky_engine 2>&1
out/host_release_arm64/dart-sdk/bin/dart --version
