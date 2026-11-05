#!/usr/bin/env bash
# Seeds a demo app through the CLI protocol: one Android release with three
# artifacts, patch 1 (rolled back) and patch 2 (live on stable), one device
# check and one install event. For looking at the console without a device.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; set -a; . "$ROOT/.env"; set +a
A="Authorization: Bearer $API_TOKEN"; U="$PUBLIC_URL/api/v1"; J='content-type: application/json'
jget() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }
APP=$(curl -fsS -H "$A" -H "$J" -d '{"display_name":"Demo app","organization_id":1}' "$U/apps" | jget 'd["id"]')
V="1.0.0+7"
RID=$(curl -fsS -H "$A" -H "$J" -d "{\"version\":\"$V\",\"flutter_revision\":\"c2c56ab2d5483bdf86152725342f55ca6faed946\",\"flutter_version\":\"3.41.7\"}" "$U/apps/$APP/releases" | jget 'd["release"]["id"]')
upload() { local f; f=$(mktemp); head -c "$3" /dev/urandom > "$f"
  local url; url=$(curl -fsS -H "$A" -F arch="$1" -F platform=android -F hash="$(shasum -a 256 "$f" | cut -d' ' -f1)" -F size="$3" -F filename="$2" -F can_sideload="$4" "$U/apps/$APP/releases/$RID/artifacts" | jget 'd["url"]')
  curl -fsS -o /dev/null -H "$A" -F file=@"$f" "$url"; rm -f "$f"; }
upload aab app-release.aab 400000 true; upload aarch64 libapp.so 120000 false; upload arm libapp.so 110000 false
curl -fsS -o /dev/null -X PATCH -H "$A" -H "$J" -d '{"status":"active","platform":"android"}' "$U/apps/$APP/releases/$RID"
CH=$(curl -fsS -H "$A" -H "$J" -d '{"channel":"stable"}' "$U/apps/$APP/channels" | jget 'd["id"]')
for _ in 1 2; do
  PID=$(curl -fsS -H "$A" -H "$J" -d "{\"release_id\":$RID,\"metadata\":{}}" "$U/apps/$APP/patches" | jget 'd["id"]')
  f=$(mktemp); head -c 9000 /dev/urandom > "$f"
  url=$(curl -fsS -H "$A" -F arch=aarch64 -F platform=android -F hash="$(shasum -a 256 "$f" | cut -d' ' -f1)" -F size=9000 "$U/apps/$APP/patches/$PID/artifacts" | jget 'd["url"]')
  curl -fsS -o /dev/null -H "$A" -F file=@"$f" "$url"; rm -f "$f"
  curl -fsS -o /dev/null -H "$A" -H "$J" -d "{\"patch_id\":$PID,\"channel_id\":$CH}" "$U/apps/$APP/patches/promote"
done
curl -fsS -o /dev/null -X POST -H "$A" "$PUBLIC_URL/api/admin/apps/$APP/releases/$V/patches/1/rollback"
curl -fsS -o /dev/null -H "$J" -d "{\"app_id\":\"$APP\",\"channel\":\"stable\",\"release_version\":\"$V\",\"platform\":\"android\",\"arch\":\"aarch64\",\"client_id\":\"a1b2c3d4-demo\"}" "$U/patches/check"
curl -fsS -o /dev/null -H "$J" -d "{\"event\":{\"app_id\":\"$APP\",\"arch\":\"aarch64\",\"client_id\":\"a1b2c3d4-demo\",\"type\":\"__patch_install__\",\"patch_number\":2,\"platform\":\"android\",\"release_version\":\"$V\",\"timestamp\":$(date +%s),\"message\":null}}" "$U/patches/events"
echo "APP=$APP RID=$RID"
