#!/usr/bin/env bash
# cURL examples for PeopleChain monitor
# Usage:
#   BASE_URL=http://192.168.1.50:8081 ./examples.sh
# Defaults to http://127.0.0.1:8081 if BASE_URL is not provided.

BASE_URL=${BASE_URL:-http://127.0.0.1:8081}

echo "== GET /api/info"
curl -sS "$BASE_URL/api/info" | jq .

echo
echo "== GET /api/peers?limit=10"
curl -sS "$BASE_URL/api/peers?limit=10" | jq .

echo
echo "== GET /api/blocks?from=tip&count=3"
curl -sS "$BASE_URL/api/blocks?from=tip&count=3" | jq .

echo
echo "# WebSocket: use websocat or wscat to try /ws"
echo "# Example (wscat): npx wscat -c \"${BASE_URL/http/ws}/ws\" -x '{\"type\":\"get_info\"}'"
