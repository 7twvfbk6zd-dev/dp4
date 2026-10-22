#!/usr/bin/env bash
set -euo pipefail

BASE=${NEW_API_BASE:-http://127.0.0.1:30300}
ADMIN_USER=${NEW_API_ADMIN_USER:-admin}
ADMIN_PASS=${NEW_API_ADMIN_PASSWORD:?set NEW_API_ADMIN_PASSWORD}
UPSTREAM=${DS4_UPSTREAM:-http://ds4.ds4.svc.cluster.local:18080}
UPSTREAM_KEY=${DS4_API_KEY:-sk-local}
MODEL=${DS4_MODEL_ID:-deepseek-v4.1-flash}

json_get() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"
}

SETUP=$(curl -fsS "$BASE/api/setup")
if [ "$(printf '%s' "$SETUP" | json_get 'str(d.get("data",{}).get("status",False)).lower()')" != "true" ]; then
  curl -fsS -X POST "$BASE/api/setup" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\",\"confirmPassword\":\"$ADMIN_PASS\",\"SelfUseModeEnabled\":true,\"DemoSiteEnabled\":false}" >/dev/null
fi

LOGIN=$(curl -fsS -X POST "$BASE/api/user/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")
ACCESS_TOKEN=$(printf '%s' "$LOGIN" | json_get 'd["data"]["access_token"]')
AUTH="Authorization: Bearer $ACCESS_TOKEN"

CHANNELS=$(curl -fsS -H "$AUTH" "$BASE/api/channel/?p=0&page_size=100")
CHANNEL_ID=$(printf '%s' "$CHANNELS" | json_get 'next((x["id"] for x in (d.get("data",{}).get("items") or []) if x.get("name")=="ds4-local"), "")')
if [ -z "$CHANNEL_ID" ]; then
  curl -fsS -H "$AUTH" -X POST "$BASE/api/channel/" \
    -H 'Content-Type: application/json' \
    -d "{\"mode\":\"single\",\"channel\":{\"name\":\"ds4-local\",\"type\":1,\"key\":\"$UPSTREAM_KEY\",\"base_url\":\"$UPSTREAM\",\"models\":\"$MODEL\",\"group\":\"default\",\"status\":1}}" >/dev/null
fi

TOKENS=$(curl -fsS -H "$AUTH" "$BASE/api/token/?p=0&page_size=100")
TOKEN_ID=$(printf '%s' "$TOKENS" | json_get 'next((x["id"] for x in (d.get("data",{}).get("items") or []) if x.get("name")=="chatbox"), "")')
if [ -z "$TOKEN_ID" ]; then
  curl -fsS -H "$AUTH" -X POST "$BASE/api/token/" \
    -H 'Content-Type: application/json' \
    -d '{"name":"chatbox","remain_quota":0,"unlimited_quota":true,"expired_time":-1,"group":"default","model_limits_enabled":false,"model_limits":"","allow_ips":"","cross_group_retry":false}' >/dev/null
  TOKENS=$(curl -fsS -H "$AUTH" "$BASE/api/token/?p=0&page_size=100")
  TOKEN_ID=$(printf '%s' "$TOKENS" | json_get 'next((x["id"] for x in (d.get("data",{}).get("items") or []) if x.get("name")=="chatbox"), "")')
fi

KEY_JSON=$(curl -fsS -H "$AUTH" -X POST "$BASE/api/token/$TOKEN_ID/key")
printf '%s' "$KEY_JSON" | json_get 'd["data"]["key"]'
