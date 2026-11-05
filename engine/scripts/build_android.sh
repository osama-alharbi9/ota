#!/usr/bin/env bash
# Build an Android release engine (libflutter.so with the Rust updater,
# embedding jars/poms, gen_snapshot for the host) against stock Dart.
# Usage: build_android.sh [arm64|arm|x64]   (default arm64)
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_engine_version
CPU="${1:-arm64}"
case "$CPU" in
  arm64) OUT=out/android_release_arm64 ;;
  arm)   OUT=out/android_release ;;
  x64)   OUT=out/android_release_x64 ;;
  *) echo "unknown cpu $CPU"; exit 1 ;;
esac
TARGETS=(default flutter/shell/platform/android:gen_snapshot)
# The Dart packages sky_engine and flutter_gpu are the same for every ABI and
# mode. Upstream zips them in its Android CI config (linux_android_debug_engine.json);
# we build them once, with arm64 (zip_archives/sky_engine.zip, flutter_gpu.zip).
if [ "$CPU" = arm64 ]; then
  TARGETS+=(flutter/sky/dist:zip_old_location flutter/lib/gpu/dist:zip_old_location)
fi
cd "$ENGINE_SRC"
# Native arm64 host tools on Apple Silicon (Shorebird's CI forces host_cpu=x64
# for Intel compatibility; we do not need that).
./flutter/tools/gn --no-rbe --no-enable-unittests --android --android-cpu="$CPU" \
  --runtime-mode=release --gn-args='host_cpu="arm64"'
time "$NINJA" -C "$OUT" -j "$JOBS" "${TARGETS[@]}"
ls -la "$OUT/lib.stripped/libflutter.so" "$OUT"/*.pom
find "$OUT" -maxdepth 2 -name gen_snapshot -type f
# Provenance: our build must not contain any Shorebird name or host.
if strings "$OUT/lib.stripped/libflutter.so" | grep -qi shorebird; then
  echo "FAIL: libflutter.so contains 'shorebird'"; strings "$OUT/lib.stripped/libflutter.so" | grep -i shorebird | head; exit 1
fi
echo "libflutter.so ($CPU): no 'shorebird' strings"
