#!/usr/bin/env bash
# demo/seed.sh — seed one transcript batch into the approval queue, stopping at
# PENDING_REGISTRAR. Replicates steps 1–6 of CrossServiceHappyPathIT; it performs
# NO approvals — registrar/dean decisions are the human's job in the demo.
#
# The demo is fixed to institution 01110: the batch is created with INSTITUTION_CODE
# and the transcript-e2e token's institution_code claim is hardcoded to 01110 by the
# realm mapper, so an XML for any other institution is still batched under 01110.
#
# Driven entirely by env so the same script runs inside the demo-seed container and
# via demo/ingest.sh. Requires: bash, curl, jq.
set -euo pipefail

PROCESSING_URL="${PROCESSING_URL:-http://transcript-processing:8085}"
ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://transcript-orchestrator:8095}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
CLIENT_SECRET="${CLIENT_SECRET:-e2e-dev-secret}"
INSTITUTION_CODE="${INSTITUTION_CODE:-01110}"
FIXTURE_PATH="${FIXTURE_PATH:-/fixtures/input.xml}"

BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT
fail() { echo "demo-seed: ERROR: $*" >&2; exit 1; }

# ── Step 1: ingest the transcript XML ─────────────────────────────────────────
status=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST \
  "$PROCESSING_URL/api/v1/transcripts" \
  -H 'Content-Type: application/xml' \
  --data-binary "@$FIXTURE_PATH")
# transcript-processing keys on <tc:TranscriptID>. A re-ingest of identical
# content returns 200 {"error":"Duplicate transcript","message":"...
# with documentId: <id>"} — treat it as a clean no-op so a re-run of
# up.sh / ingest.sh against a dirty volume does not break the demo.
if [ "$status" = "200" ] && [ "$(jq -r '.error // empty' < "$BODY")" = "Duplicate transcript" ]; then
  dup_id=$(jq -r '.message // ""' < "$BODY" | grep -oE '[0-9A-Za-z]+$' || true)
  echo "demo-seed: transcript already ingested (documentId=${dup_id:-?}); it is already batched."
  echo "demo-seed: nothing to do — to seed a NEW batch, ingest a transcript with a different"
  echo "demo-seed: <tc:TranscriptID>, or run ./demo/down.sh to reset the stack and start fresh."
  exit 0
fi
[ "$status" = "202" ] || fail "ingest expected 202 (or 200 Duplicate), got $status: $(cat "$BODY")"
document_id=$(jq -r '.documentId' < "$BODY")
[ -n "$document_id" ] && [ "$document_id" != "null" ] || fail "no documentId: $(cat "$BODY")"
echo "demo-seed: ingested documentId=$document_id"

# ── Step 2: mint a transcript-e2e client-credentials token ────────────────────
status=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST \
  "$KEYCLOAK_URL/realms/transcript/protocol/openid-connect/token" \
  -d grant_type=client_credentials \
  -d client_id=transcript-e2e \
  -d "client_secret=$CLIENT_SECRET")
[ "$status" = "200" ] || fail "token expected 200, got $status: $(cat "$BODY")"
token=$(jq -r '.access_token' < "$BODY")
[ -n "$token" ] && [ "$token" != "null" ] || fail "no access_token: $(cat "$BODY")"
auth="Authorization: Bearer $token"

# ── Step 3: poll the orchestrator until the TranscriptItem appears ────────────
# (For 202-new-item case; the 200-Duplicate case above exits before reaching here.)
item_id=""
for _ in $(seq 1 15); do
  status=$(curl -sS -o "$BODY" -w '%{http_code}' -H "$auth" \
    "$ORCHESTRATOR_URL/api/v1/transcripts")
  [ "$status" = "200" ] || fail "list transcripts expected 200, got $status: $(cat "$BODY")"
  item_id=$(jq -r --arg d "$document_id" \
    'map(select(.documentId == $d)) | .[0].id // empty' < "$BODY")
  [ -n "$item_id" ] && break
  sleep 2
done
[ -n "$item_id" ] || fail "TranscriptItem for documentId=$document_id did not appear within 30s"
echo "demo-seed: TranscriptItem id=$item_id"

# ── Step 4: create the batch ──────────────────────────────────────────────────
status=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST \
  "$ORCHESTRATOR_URL/api/v1/batches" \
  -H "$auth" -H 'Content-Type: application/json' \
  -d "{\"name\":\"Demo-Batch\",\"institutionCode\":\"$INSTITUTION_CODE\",\"createdBy\":\"demo-seed\"}")
[ "$status" = "201" ] || fail "create batch expected 201, got $status: $(cat "$BODY")"
batch_id=$(jq -r '.batchId' < "$BODY")
[ -n "$batch_id" ] && [ "$batch_id" != "null" ] || fail "no batchId: $(cat "$BODY")"

# ── Step 5: assign the item to the batch ──────────────────────────────────────
status=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST \
  "$ORCHESTRATOR_URL/api/v1/batches/$batch_id/items" \
  -H "$auth" -H 'Content-Type: application/json' \
  -d "{\"itemIds\":[\"$item_id\"]}")
case "$status" in 200|201|204) ;; *) fail "assign item expected 2xx, got $status: $(cat "$BODY")";; esac

# ── Step 6: close the batch → PENDING_REGISTRAR ───────────────────────────────
status=$(curl -sS -o "$BODY" -w '%{http_code}' -X POST \
  "$ORCHESTRATOR_URL/api/v1/batches/$batch_id/close" \
  -H "$auth" -H 'X-Closed-By: demo-seed')
case "$status" in 200|204) ;; *) fail "close batch expected 200/204, got $status: $(cat "$BODY")";; esac

echo "demo-seed: SUCCESS — batch $batch_id is now PENDING_REGISTRAR."
echo "demo-seed: log into http://localhost:8081 as registrar1 to approve it."
