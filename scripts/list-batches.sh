#!/usr/bin/env bash
set -euo pipefail

# List batches with optional status filtering
# Usage: ./scripts/list-batches.sh [status] [page] [size]

STATUS="${1:-}"
PAGE="${2:-}"
SIZE="${3:-}"

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://localhost:8095}"

# Source shared auth helper (Keycloak client-credentials grant).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_monitor_common.sh
source "${SCRIPT_DIR}/_monitor_common.sh"

# Build query parameters
QUERY_PARAMS=()
if [ -n "$STATUS" ]; then
    QUERY_PARAMS+=("status=$STATUS")
fi
if [ -n "$PAGE" ]; then
    QUERY_PARAMS+=("page=$PAGE")
fi
if [ -n "$SIZE" ]; then
    QUERY_PARAMS+=("size=$SIZE")
fi

# Construct URL
URL="$ORCHESTRATOR_URL/api/v1/batches"
if [ ${#QUERY_PARAMS[@]} -gt 0 ]; then
    URL="${URL}?$(IFS='&'; echo "${QUERY_PARAMS[*]}")"
fi

echo "Fetching batches from: $URL"
echo ""

# Get batches (authenticated via Keycloak service-account JWT)
RESPONSE=$(auth_curl "$URL")

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE" | jq -r '.error')
    echo "Error: $ERROR"
    exit 1
fi

# Parse and display
BATCH_COUNT=$(echo "$RESPONSE" | jq 'length')
echo "Found $BATCH_COUNT batch(es)"
echo ""

if [ "$BATCH_COUNT" -eq 0 ]; then
    echo "No batches found"
    exit 0
fi

# Display batches in a formatted table
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%-40s %-15s %-20s %-8s %-12s\n" "BATCH ID" "STATUS" "INSTITUTION" "ITEMS" "CREATED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "$RESPONSE" | jq -r '.[] | [
    .id,
    .status,
    .institutionCode,
    (.itemCount | tostring),
    (.createdAt[0:19] // "N/A")
] | @tsv' | while IFS=$'\t' read -r BATCH_ID STATUS INSTITUTION ITEMS CREATED; do
    # Add emoji indicators for key states
    case "$STATUS" in
        PENDING_REGISTRAR)
            STATUS="⏳ $STATUS"
            ;;
        PENDING_DEAN)
            STATUS="⏳ $STATUS"
            ;;
        COMPLETED)
            STATUS="✅ $STATUS"
            ;;
        FAILED)
            STATUS="❌ $STATUS"
            ;;
        CANCELLED)
            STATUS="🚫 $STATUS"
            ;;
        DRAFT)
            STATUS="📝 $STATUS"
            ;;
        *)
            STATUS="⚙️  $STATUS"
            ;;
    esac

    printf "%-40s %-15s %-20s %-8s %-12s\n" "$BATCH_ID" "$STATUS" "$INSTITUTION" "$ITEMS" "$CREATED"
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To watch a specific batch:"
echo "  ./scripts/watch-batch.sh <batch-id>"
echo ""
echo "Available statuses: DRAFT, PENDING_REGISTRAR, REGISTRAR_SIGNING, PENDING_DEAN,"
echo "                    DEAN_SIGNING, SEALING, PDF_GENERATION, PDF_SIGNING,"
echo "                    COMPLETED, CANCELLED, FAILED"
