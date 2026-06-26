#!/usr/bin/env bash
set -euo pipefail

# Watch a single batch's state changes in real-time
# Usage: ./scripts/watch-batch.sh <batch-id> [poll-interval-seconds]

BATCH_ID="${1:-}"
POLL_INTERVAL="${2:-2}"

if [ -z "$BATCH_ID" ]; then
    echo "Usage: $0 <batch-id> [poll-interval-seconds]"
    echo ""
    echo "Example:"
    echo "  $0 123e4567-e89b-12d3-a456-426614174000 5"
    echo ""
    echo "To find batch IDs:"
    echo "  curl http://localhost:8095/api/v1/batches | jq '.[].id'"
    exit 1
fi

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://localhost:8095}"

# Source path resolution: this script lives in scripts/, helper in same dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_monitor_common.sh
source "${SCRIPT_DIR}/_monitor_common.sh"

echo "Watching batch: $BATCH_ID"
echo "Poll interval: ${POLL_INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

LAST_STATUS=""

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Get batch details
    RESPONSE=$(auth_curl "${ORCHESTRATOR_URL}/api/v1/batches/${BATCH_ID}" || echo '{"error": "API unavailable"}')

    # Check if batch exists
    if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        echo "[$TIMESTAMP] Error: $(echo "$RESPONSE" | jq -r '.error')"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Extract status and other key fields
    STATUS=$(echo "$RESPONSE" | jq -r '.status // "UNKNOWN"')
    NAME=$(echo "$RESPONSE" | jq -r '.name // "N/A"')
    ITEM_COUNT=$(echo "$RESPONSE" | jq -r '.itemCount // 0')
    FAILURE_REASON=$(echo "$RESPONSE" | jq -r '.failureReason // ""')
    REJECTION_REASON=$(echo "$RESPONSE" | jq -r '.rejectionReason // ""')

    # Only print if status changed or it's the first run
    if [ "$STATUS" != "$LAST_STATUS" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "[$TIMESTAMP] Status: $STATUS"
        echo "  Batch: $NAME ($ITEM_COUNT items)"

        # Show human gates
        if [ "$STATUS" = "PENDING_REGISTRAR" ]; then
            echo "  ⏳ Waiting for registrar approval"
        elif [ "$STATUS" = "PENDING_DEAN" ]; then
            echo "  ⏳ Waiting for dean approval"
        fi

        # Show completion
        if [ "$STATUS" = "COMPLETED" ]; then
            COMPLETED_AT=$(echo "$RESPONSE" | jq -r '.completedAt // "N/A"')
            echo "  ✅ Completed at: $COMPLETED_AT"
        fi

        # Show failures
        if [ -n "$FAILURE_REASON" ]; then
            echo "  ❌ Failed: $FAILURE_REASON"
        fi
        if [ -n "$REJECTION_REASON" ]; then
            echo "  🚫 Rejected: $REJECTION_REASON"
        fi

        # Show approvals if present
        REGISTRAR_APPROVER=$(echo "$RESPONSE" | jq -r '.registrarApprovedBy // ""')
        DEAN_APPROVER=$(echo "$RESPONSE" | jq -r '.deanApprovedBy // ""')

        if [ -n "$REGISTRAR_APPROVER" ]; then
            REGISTRAR_TIME=$(echo "$RESPONSE" | jq -r '.registrarApprovedAt // "N/A"')
            echo "  📝 Registrar approved by: $REGISTRAR_APPROVER at $REGISTRAR_TIME"
        fi

        if [ -n "$DEAN_APPROVER" ]; then
            DEAN_TIME=$(echo "$RESPONSE" | jq -r '.deanApprovedAt // "N/A"')
            echo "  📝 Dean approved by: $DEAN_APPROVER at $DEAN_TIME"
        fi

        LAST_STATUS="$STATUS"

        # Exit if terminal state reached
        if [ "$STATUS" = "COMPLETED" ] || [ "$STATUS" = "CANCELLED" ] || [ "$STATUS" = "FAILED" ]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "[$TIMESTAMP] Terminal state reached: $STATUS"
            exit 0
        fi
    else
        # Show we're still watching (every 10 cycles)
        if [ $((RANDOM % 10)) -eq 0 ]; then
            echo "[$TIMESTAMP] Still watching... (current: $STATUS)"
        fi
    fi

    sleep "$POLL_INTERVAL"
done
