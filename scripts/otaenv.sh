#!/usr/bin/env bash
# Source this to point the ota CLI at the server in .env without `ota login`:
#   source scripts/otaenv.sh
# OTA_ENV_FILE picks another file with the same settings, e.g. a staging server's.
_OTA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
set -a; . "${OTA_ENV_FILE:-$_OTA_ROOT/.env}"; set +a
export OTA_HOSTED_URL="$PUBLIC_URL"
export OTA_TOKEN="$API_TOKEN"
export PATH="$_OTA_ROOT/cli/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
echo "ota CLI -> $OTA_HOSTED_URL (token ${OTA_TOKEN:0:12}...)"
