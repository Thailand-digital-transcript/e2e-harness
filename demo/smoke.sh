#!/usr/bin/env bash
# demo/smoke.sh — assert the demo is live: a seeded batch is PENDING_REGISTRAR,
# reachable from the host via the orchestrator REST API. Run after demo/up.sh.
# Requires host curl + jq.
set -euo pipefail

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://localhost:8095}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
CLIENT_SECRET="${CLIENT_SECRET:-e2e-dev-secret}"

token=$(curl -sS -X POST \
  "$KEYCLOAK_URL/realms/transcript/protocol/openid-connect/token" \
  -d grant_type=client_credentials -d client_id=transcript-e2e \
  -d "client_secret=$CLIENT_SECRET" | jq -r '.access_token')
[ -n "$token" ] && [ "$token" != "null" ] || { echo "smoke: could not mint token" >&2; exit 1; }

body=$(curl -sS -H "Authorization: Bearer $token" \
  "$ORCHESTRATOR_URL/api/v1/batches?status=PENDING_REGISTRAR")
count=$(echo "$body" | jq '[.[] | select(.status == "PENDING_REGISTRAR")] | length')
if [ "${count:-0}" -ge 1 ]; then
  if [ "$count" = "1" ]; then noun="batch"; else noun="batches"; fi
  echo "smoke: OK — $count $noun in PENDING_REGISTRAR."
else
  echo "smoke: FAIL — no PENDING_REGISTRAR batch. Response: $body" >&2
  exit 1
fi
