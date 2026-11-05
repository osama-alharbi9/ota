#!/usr/bin/env bash
# Assemble the artifact server's root from OUR build outputs only.
# Layout mirrors the bucket paths the tools request:
#   ota/<engine>/patch-darwin-x64.zip                        (ota CLI PatchArtifact)
#   flutter_infra_release/flutter/<engine>/<zip_archives path> (flutter_tools cache)
#   download.flutter.io/io/flutter/<id>/1.0.0-<engine>/...     (Gradle, embedding + libflutter)
# What is served, and why each deviation from upstream's layout is safe: CLEANROOM T1-17.
set -euo pipefail
source "$(dirname "$0")/env.sh"
check_engine_version
E=$(engine_commit)
OUT="$ENGINE_SRC/out"
HOST="$OUT/host_release_arm64"
# Android configs to publish: all three ABIs unless a trial names a subset.
read -r -a ANDROID_OUTS <<< "${MIRROR_ANDROID_OUTS:-android_release_arm64 android_release android_release_x64}"
for a in "${ANDROID_OUTS[@]}"; do
  ls "$OUT/$a/lib.stripped/libflutter.so" "$OUT/$a"/*_release.jar >/dev/null 2>&1 \
    || { echo "$a is not fully built (build_android.sh)"; exit 1; }
done
rm -rf "$MIRROR_DIR"; mkdir -p "$MIRROR_DIR"
F="$MIRROR_DIR/flutter_infra_release/flutter/$E"

# 1. patch tool (public updater repo, built by build_patch_tool.sh)
d="$MIRROR_DIR/revon/$E"  # the CLI reads this prefix: toolchainArtifactPrefix; mkdir -p "$d"
( cd "$UPDATER_SRC/target/release" && zip -q -X "$d/patch-darwin-x64.zip" patch )

# 2. engine_stamp.json ("engine information" in flutter_tools), written by
#    upstream's own generator (engine_tool `et stamp`) with our Dart SDK.
( cd "$ENGINE_SRC/flutter" && "$HOST/dart-sdk/bin/dart" tools/engine_tool/bin/et.dart stamp )

# 3. every zip archive the engine builds produced, at the same relative path
#    upstream CI uploads it to (zip_archives/<p> -> flutter_infra_release/flutter/<hash>/<p>)
for cfg in host_release_arm64 "${ANDROID_OUTS[@]}"; do
  za="$OUT/$cfg/zip_archives"; [ -d "$za" ] || continue
  ( cd "$za" && find . -type f ) | while read -r f; do
    mkdir -p "$F/$(dirname "$f")"
    cp "$za/$f" "$F/$f"
  done
done
cp "$OUT/engine_stamp.json" "$F/"

# 4. The Dart SDK zip, made with upstream's build/zip.py from our from-source SDK
#    (the GN target cannot make it on macOS; see build_host.sh).
python3 "$ENGINE_SRC/flutter/build/zip.py" -o "$F/dart-sdk-darwin-arm64.zip" \
  -i "$HOST/dart-sdk" dart-sdk \
  -i "$HOST/gen/flutter/build/archives/dart_sdk_entitlements.txt" entitlements.txt

# 5. darwin-arm64/artifacts.zip: host tools flutter_tools unpacks into
#    engine/darwin-x64. Upstream zips it only in a debug host build (its release
#    variant holds just gen_snapshot and analyze_snapshot). We build release only,
#    so it is packed here, with upstream's zip.py and upstream's file names, from
#    the mode-independent tools of our release host build: impellerc and shader_lib
#    (shader compilation, used by every Android release build), the tessellator
#    and path_ops libraries, icudtl.dat, gen_snapshot and analyze_snapshot.
#    Left out: flutter_tester and the JIT snapshots, which exist only for debug
#    (`flutter test`), so that path fails plainly on this toolchain.
A="$HOST/gen/flutter/build/archives"
python3 "$ENGINE_SRC/flutter/build/zip.py" -o "$F/darwin-arm64/artifacts.zip" \
  -i "$A/LICENSE.artifacts.md" LICENSE.artifacts.md \
  -i "$A/entitlements.txt" entitlements.txt \
  -i "$HOST/impellerc" impellerc \
  -i "$ENGINE_SRC/flutter/impeller/compiler/shader_lib" shader_lib \
  -i "$HOST/libtessellator.dylib" libtessellator.dylib \
  -i "$HOST/libpath_ops.dylib" libpath_ops.dylib \
  -i "$ENGINE_SRC/flutter/third_party/icu/flutter/icudtl.dat" icudtl.dat \
  -i "$HOST/gen_snapshot" gen_snapshot \
  -i "$HOST/analyze_snapshot" analyze_snapshot

# 6. Maven artifacts for Gradle (embedding jar + per-ABI libflutter jar)
for cfg in "${ANDROID_OUTS[@]}"; do
  for pom in "$OUT/$cfg"/*.pom; do
    [ -f "$pom" ] || continue
    id=$(basename "$pom" .pom); v="1.0.0-$E"
    grep -q "<version>$v</version>" "$pom" || { echo "POM $pom is not version $v"; exit 1; }
    dst="$MIRROR_DIR/download.flutter.io/io/flutter/$id/$v"
    # flutter_embedding_release is built by every ABI config; the copies differ
    # only by an empty tmp_<random>/.empty entry the jar step leaks. First wins (arm64).
    [ -e "$dst/$id-$v.jar" ] && continue
    mkdir -p "$dst"
    cp "$pom" "$dst/$id-$v.pom"; cp "${pom%.pom}.jar" "$dst/$id-$v.jar"
  done
done

( cd "$MIRROR_DIR" && find . -type f | sort | while read -r f; do
    printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -c1-16)" "$f"; done ) | tee "$ENGINE_WS/mirror_manifest.txt"
