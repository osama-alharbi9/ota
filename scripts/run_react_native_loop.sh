#!/usr/bin/env bash
# End-to-end test of React Native updates on a real emulator or simulator:
# release, patch, automatic rollback of a crashing patch, and server rollback.
#
#   docker compose -f compose.yaml -f compose.dev.yaml --env-file .env.dev up -d --build
#   scripts/run_react_native_loop.sh android   # a running emulator
#   scripts/run_react_native_loop.sh ios       # a booted simulator
#
# The example app must have an ota.yaml from `ota init` that points at this server.
set -euo pipefail
PLATFORM="${1:?usage: run_react_native_loop.sh android|ios}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/examples/react-native"
set -a; . "${OTA_ENV_FILE:-$ROOT/.env.dev}"; set +a
export OTA_HOSTED_URL="$PUBLIC_URL" OTA_TOKEN="$API_TOKEN"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$ROOT/cli/bin:$ANDROID_HOME/platform-tools:$PATH"
export LANG="${LANG:-en_US.UTF-8}" LC_ALL="${LC_ALL:-en_US.UTF-8}" # CocoaPods fails without UTF-8
PACKAGE=dev.ota.example
SOURCE="$APP/App.tsx"
BUILD_FILE="$APP/android/app/build.gradle"
XCODE_PROJECT="$APP/ios/OtaExample.xcodeproj/project.pbxproj"
OUT="$(mktemp -d)"
BUILD="$(date +%s)"
VERSION="1.0+$BUILD"
cp "$SOURCE" "$OUT/App.tsx.orig"
cp "$BUILD_FILE" "$OUT/build.gradle.orig"
cp "$XCODE_PROJECT" "$OUT/project.pbxproj.orig"
restore() {
  cp "$OUT/App.tsx.orig" "$SOURCE"
  cp "$OUT/build.gradle.orig" "$BUILD_FILE"
  cp "$OUT/project.pbxproj.orig" "$XCODE_PROJECT"
}
trap restore EXIT

step() { echo; echo "=== [$(date -u +%T)] $*"; }
fail() { echo "FAIL: $*"; echo "logs in $OUT"; exit 1; }
set_label() { sed -i '' -E "s/^const LABEL = '.*';/const LABEL = '$1';/" "$SOURCE"; }

if [ "$PLATFORM" = android ]; then
  build_app() {
    sed -i '' -E "s/versionCode [0-9]+/versionCode $BUILD/" "$BUILD_FILE"
    (cd "$APP/android" && ./gradlew assembleRelease -q -PreactNativeArchitectures="${ANDROID_ABI:-arm64-v8a}" 2>&1 | grep -vE '^w: |warning:' || true)
    adb install -r "$APP/android/app/build/outputs/apk/release/app-release.apk" >/dev/null
    adb reverse tcp:8080 tcp:8080 >/dev/null
  }
  launch() {
    # Starts the app, waits for the update check to finish, then records its logs.
    adb logcat -c
    adb shell am force-stop "$PACKAGE"
    adb shell am start -W -n "$PACKAGE/.MainActivity" >/dev/null
    sleep "${1:-7}"
    adb logcat -d -s ReactNativeJS:I ota:I AndroidRuntime:E > "$OUT/last.log" || true
    LAST_LABEL="$(grep -o 'OTA_EXAMPLE_LABEL=.*' "$OUT/last.log" | tail -1 | cut -d= -f2 | tr -d '\r' || true)"
  }
else
  UDID="${IOS_UDID:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)}"
  [ -n "$UDID" ] || fail "no booted simulator"
  build_app() {
    sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/" "$XCODE_PROJECT"
    (cd "$APP/ios" && pod install >/dev/null)
    xcodebuild -quiet -workspace "$APP/ios/OtaExample.xcworkspace" -scheme OtaExample -configuration Release \
      -sdk iphonesimulator -destination "id=$UDID" -derivedDataPath "$APP/ios/build" build 2>&1 | grep -E 'error:|BUILD FAILED' || true
    xcrun simctl install "$UDID" "$APP/ios/build/Build/Products/Release-iphonesimulator/OtaExample.app"
  }
  launch() {
    local started
    started="$(date '+%Y-%m-%d %H:%M:%S')"
    xcrun simctl terminate "$UDID" "$PACKAGE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$PACKAGE" >/dev/null
    sleep "${1:-7}"
    xcrun simctl spawn "$UDID" log show --start "$started" --info --style compact \
      --predicate 'process == "OtaExample"' > "$OUT/last.log" 2>/dev/null || true
    LAST_LABEL="$(grep -ao 'OTA_EXAMPLE_LABEL=.*' "$OUT/last.log" | tail -1 | cut -d= -f2 | tr -d '\r' || true)"
  }
fi

expect_label() {
  [ "$LAST_LABEL" = "$1" ] || { cat "$OUT/last.log" | tail -30; fail "expected label '$1', got '$LAST_LABEL'"; }
  echo "    running: $LAST_LABEL"
}
expect_log() {
  grep -aq "$1" "$OUT/last.log" || { tail -30 "$OUT/last.log"; fail "expected log line '$1'"; }
  echo "    log: $1"
}

curl -fsS -m 5 -o /dev/null "$PUBLIC_URL/api/v1/users/me" -H "Authorization: Bearer $API_TOKEN" || fail "server is not running at $PUBLIC_URL"
cd "$APP"
set_label 'RELEASE v1'

step "build and install the native app, version $VERSION"
build_app

step "ota release react-native"
ota release react-native --platforms="$PLATFORM"

step "A1: first launch runs the bundle inside the app"
launch
expect_label 'RELEASE v1'

step "ota patch react-native: patch 1"
set_label 'PATCH v2'
ota patch react-native --platforms="$PLATFORM"

step "A2: this launch downloads patch 1 and still runs the release"
launch
expect_label 'RELEASE v1'

step "A3: the next launch runs patch 1"
launch
expect_label 'PATCH v2'

step "ota patch react-native: patch 2 crashes on start"
sed -i '' "s/^console.log(\`OTA_EXAMPLE_LABEL=\${LABEL}\`);/&\nthrow new Error('OTA_EXAMPLE_CRASH');/" "$SOURCE"
ota patch react-native --platforms="$PLATFORM"
cp "$OUT/App.tsx.orig" "$SOURCE"
set_label 'PATCH v2'

step "B1: this launch downloads patch 2"
launch
expect_label 'PATCH v2'

step "B2: the next launch boots patch 2, which crashes"
launch 5
expect_log 'OTA_EXAMPLE_CRASH'

step "B3: the launch after that drops patch 2 and returns to patch 1"
launch
expect_label 'PATCH v2'

step "B4: patch 2 is never downloaded or booted again"
launch
expect_label 'PATCH v2'

step "ota patches rollback: patch 1"
ota patches rollback --release-version "$VERSION" --patch-number 1

step "C1: this launch learns about the rollback and keeps running"
launch
expect_label 'PATCH v2'

step "C2: the next launch is back on the release"
launch
expect_label 'RELEASE v1'

step "server events for $VERSION"
docker compose --project-directory "$ROOT" -f "$ROOT/compose.yaml" -f "$ROOT/compose.dev.yaml" --env-file "${OTA_ENV_FILE:-$ROOT/.env.dev}" logs api 2>/dev/null \
  | grep -a 'patch event' | grep -a "$BUILD" | grep -aoE '"type":"[a-z_]+"|"patch_number":[0-9]+' | paste - - | sed 's/^/    /' || true

echo
echo "PASS: $PLATFORM release, patch, crash rollback and server rollback"
