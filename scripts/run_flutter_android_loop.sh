#!/usr/bin/env bash
# End-to-end test of Flutter updates on a running Android emulator: release, patch
# and server rollback, using the example in examples/flutter.
#
#   docker compose -f compose.yaml -f compose.dev.yaml --env-file .env.dev up -d --build
#   scripts/run_flutter_android_loop.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/examples/flutter"
set -a; . "${OTA_ENV_FILE:-$ROOT/.env.dev}"; set +a
export OTA_HOSTED_URL="$PUBLIC_URL" OTA_TOKEN="$API_TOKEN"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$ROOT/cli/bin:$ANDROID_HOME/platform-tools:$PATH"
PACKAGE=dev.ota.sample
MAIN="$APP/lib/main.dart"
OUT="$(mktemp -d)"
BUILD="$(date +%s)"
VERSION="1.0.0+$BUILD"
cp "$MAIN" "$OUT/main.dart.orig"
trap 'cp "$OUT/main.dart.orig" "$MAIN"' EXIT

step() { echo; echo "=== [$(date -u +%T)] $*"; }
fail() { echo "FAIL: $*"; echo "logs in $OUT"; exit 1; }
set_label() { sed -i '' -E "s/^const String kBuildLabel = '.*';/const String kBuildLabel = '$1';/" "$MAIN"; }
launch() {
  adb logcat -c
  adb shell am force-stop "$PACKAGE"
  adb shell am start -W -n "$PACKAGE/.MainActivity" >/dev/null
  sleep "${1:-8}"
  adb logcat -d -s flutter:I updater:I > "$OUT/last.log" || true
  LAST_LABEL="$(grep -o 'SAMPLE_APP_BUILD_LABEL=.*' "$OUT/last.log" | tail -1 | cut -d= -f2 | tr -d '\r' || true)"
}
expect_label() {
  [ "$LAST_LABEL" = "$1" ] || { tail -30 "$OUT/last.log"; fail "expected label '$1', got '$LAST_LABEL'"; }
  echo "    running: $LAST_LABEL"
}

curl -fsS -m 5 -o /dev/null "$PUBLIC_URL/api/v1/users/me" -H "Authorization: Bearer $API_TOKEN" || fail "server is not running at $PUBLIC_URL"
cd "$APP"
adb reverse tcp:8080 tcp:8080 >/dev/null
set_label 'RELEASE v1'

step "ota release android, version $VERSION"
ota release android --build-number="$BUILD" --target-platform=android-arm64 --artifact=apk 2>&1 | tail -6
adb install -r "$APP/build/app/outputs/flutter-apk/app-release.apk" >/dev/null

step "A1: first launch runs the release"
launch
expect_label 'RELEASE v1'

step "ota patch android: patch 1"
set_label 'PATCH v2'
ota patch android --release-version="$VERSION" 2>&1 | tail -8

step "A2: this launch downloads patch 1"
launch
expect_label 'RELEASE v1'

step "A3: the next launch runs patch 1"
launch
expect_label 'PATCH v2'

step "ota patches rollback: patch 1"
ota patches rollback --release-version "$VERSION" --patch-number 1

step "B1: this launch learns about the rollback"
launch
step "B2: the next launch is back on the release"
launch
expect_label 'RELEASE v1'

echo
echo "PASS: Flutter Android release, patch and rollback"
