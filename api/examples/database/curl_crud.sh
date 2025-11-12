#!/usr/bin/env bash
# PeopleChain Monitor • cURL CRUD cheat sheet
#
# Usage:
#   bash curl_crud.sh

set -euo pipefail

BASE=${PC_BASE:-http://127.0.0.1:8081}
COL=notes

echo "1) Create two docs"
R1=$(curl -sS -X POST "$BASE/api/db/$COL" -H 'Content-Type: application/json' -d '{"data":{"title":"First","body":"Hello from cURL","tags":["demo","curl"]}}')
R2=$(curl -sS -X POST "$BASE/api/db/$COL" -H 'Content-Type: application/json' -d '{"data":{"title":"Second","body":"Filter me","tags":["filter"]}}')
echo "$R1"; echo "$R2"

ID1=$(echo "$R1" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
ID2=$(echo "$R2" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

echo
echo "2) List (limit=10)"
curl -sS "$BASE/api/db/$COL?limit=10" | jq . || true

echo
echo "3) Filter q=filter"
curl -sS "$BASE/api/db/$COL?q=filter" | jq . || true

echo
echo "4) Read first by id"
curl -sS "$BASE/api/db/$COL/$ID1" | jq . || true

echo
echo "5) Replace with PUT"
curl -sS -X PUT "$BASE/api/db/$COL/$ID1" -H 'Content-Type: application/json' -d '{"data":{"title":"Updated","body":"Replaced body","tags":["updated"]}}' | jq . || true

echo
echo "6) Patch with PATCH"
curl -sS -X PATCH "$BASE/api/db/$COL/$ID1" -H 'Content-Type: application/json' -d '{"data":{"extra":42,"tags":["updated","patched"]}}' | jq . || true

echo
echo "7) Delete second"
curl -sS -X DELETE "$BASE/api/db/$COL/$ID2" | jq . || true

echo
echo "8) List again"
curl -sS "$BASE/api/db/$COL" | jq . || true
