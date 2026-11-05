#!/usr/bin/env bash
# Smoke test for the server's auth and API keys. Run against a running API.
# Usage: scripts/platform_smoke.sh [API_BASE]   (default: http://localhost:8080)
# API_TOKEN comes from .env, or from OTA_ENV_FILE when set (e.g. a staging server's).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; set -a; . "${OTA_ENV_FILE:-$ROOT/.env}"; set +a
API="${1:-http://localhost:8080}"; J=$(mktemp); EMAIL="smoke-$(date +%s)@test.local"
step() { echo; echo "# $*"; }
step "no token -> 401";                 curl -sS -w ' HTTP %{http_code}\n' "$API/api/v1/users/me"
step "API_TOKEN from .env (bootstrapped) -> 200"; curl -sS -w ' HTTP %{http_code}\n' -H "Authorization: Bearer $API_TOKEN" "$API/api/v1/users/me"
step "register $EMAIL -> 201";          curl -sS -c "$J" -w ' HTTP %{http_code}\n' -H 'content-type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"testpass123\",\"display_name\":\"Smoke\"}" "$API/api/auth/register"
step "duplicate register -> 409";       curl -sS -w ' HTTP %{http_code}\n' -H 'content-type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"testpass123\"}" "$API/api/auth/register"
step "wrong password -> 401";           curl -sS -w ' HTTP %{http_code}\n' -H 'content-type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"nope\"}" "$API/api/auth/login"
step "login, then cookie -> /api/auth/me 200"; curl -sS -c "$J" -o /dev/null -w 'login HTTP %{http_code}\n' -H 'content-type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"testpass123\"}" "$API/api/auth/login"; curl -sS -b "$J" -w ' HTTP %{http_code}\n' "$API/api/auth/me"
step "create API key (dashboard)";      K=$(curl -sS -b "$J" -H 'content-type: application/json' -d '{"name":"laptop"}' "$API/api/dashboard/api-keys"); echo "$K"
KEY=$(echo "$K" | python3 -c 'import sys,json;print(json.load(sys.stdin)["key"])'); ID=$(echo "$K" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
step "new key -> /users/me and /organizations 200"; curl -sS -w ' HTTP %{http_code}\n' -H "Authorization: Bearer $KEY" "$API/api/v1/users/me"; curl -sS -w ' HTTP %{http_code}\n' -H "Authorization: Bearer $KEY" "$API/api/v1/organizations"
step "revoke key -> 204, then key -> 401"; curl -sS -b "$J" -o /dev/null -w 'revoke HTTP %{http_code}\n' -X DELETE "$API/api/dashboard/api-keys/$ID"; curl -sS -w ' HTTP %{http_code}\n' -H "Authorization: Bearer $KEY" "$API/api/v1/users/me"
step "unknown route -> {code,message,details} 404"; curl -sS -w ' HTTP %{http_code}\n' -H "Authorization: Bearer $API_TOKEN" "$API/api/v1/nope"
rm -f "$J"
