#!/usr/bin/env bash
set -euo pipefail

# Monitor all batches for state changes (multi-batch watcher)
# Usage: ./scripts/monitor-all-batches.sh [poll-interval-seconds]

POLL_INTERVAL="${1:-5}"

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://localhost:8095}"

# Source shared auth helper (Keycloak client-credentials grant).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_monitor_common.sh
source "${SCRIPT_DIR}/_monitor_common.sh"

# Store last known state of each batch
declare -A LAST_STATUS
declare -A LAST_ITEM_COUNT

echo "Monitoring all batches for state changes"
echo "Poll interval: ${POLL_INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Get all batches (mint_jwt is a no-op when the cached token is still valid).
    RESPONSE=$(auth_curl "${ORCHESTRATOR_URL}/api/v1/batches" || echo '{"error": "API unavailable"}')

    # Check if API is available
    if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        echo "[$TIMESTAMP] Error: API unavailable"
        sleep "$POLL_INTERVAL"
        continue
    fi

    BATCH_COUNT=$(echo "$RESPONSE" | jq 'length')

    if [ "$BATCH_COUNT" -eq 0 ]; then
        echo "[$TIMESTAMP] No batches found"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Process each batch
    echo "$RESPONSE" | jq -c '.[]' | while read -r BATCH; do
        BATCH_ID=$(echo "$BATCH" | jq -r '.id')
        STATUS=$(echo "$BATCH" | jq -r '.status')
        NAME=$(echo "$BATCH" | jq -r '.name')
        ITEMS=$(echo "$BATCH" | jq -r '.itemCount')
        INSTITUTION=$(echo "$BATCH" | jq -r '.institutionCode')

        # Check if this is a new batch or status changed
        PREV_STATUS="${LAST_STATUS[$BATCH_ID]:-}"
        PREV_ITEMS="${LAST_ITEM_COUNT[$BATCH_ID]:-}"

        if [ "$PREV_STATUS" != "$STATUS" ] || [ "$PREV_ITEMS" != "$ITEMS" ] || [ -z "$PREV_STATUS" ]; then
            STATUS_CHANGE=""
            if [ -n "$PREV_STATUS" ] && [ "$PREV_STATUS" != "$STATUS" ]; then
                STATUS_CHANGE "($PREV_STATUS → $STATUS)"
            fi

            # Format status with emoji
            case "$STATUS" in
                PENDING_REGISTRAR)
                    STATUS_ICON="⏳"
                    ;;
                PENDING_DEAN)
                    STATUS_ICON="⏳"
                    ;;
                COMPLETED)
                    STATUS_ICON="✅"
                    ;;
                FAILED)
                    STATUS_ICON="❌"
                    ;;
                CANCELLED)
                    STATUS_ICON="🚫"
                    ;;
                DRAFT)
                    STATUS_ICON="📝"
                    ;;
                *)
                    STATUS_ICON="⚙️ "
                    ;;
            esac

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "[$TIMESTAMP] $STATUS_ICON $NAME ($INSTITUTION)"
            echo "  Batch ID: $BATCH_ID"
            echo "  Status: $STATUS $STATUS_CHANGE"
            echo "  Items: $ITEMS"

            # Show approval info for human gates
            if [ "$STATUS" = "PENDING_REGISTRAR" ]; then
                echo "  Action required: Registrar approval needed"
            elif [ "$STATUS" = "PENDING_DEAN" ]; then
                echo "  Action required: Dean approval needed"
            fi

            # Show failures
            FAILURE_REASON=$(echo "$BATCH" | jq -r '.failureReason // ""')
            REJECTION_REASON=$(echo "$BATCH" | jq -r '.rejectionReason // ""')

            if [ -n "$FAILURE_REASON" ]; then
                echo "  ❌ Failure: $FAILURE_REASON"
            fi
            if [ -n "$REJECTION_REASON" ]; then
                echo "  🚫 Rejection: $REJECTION_REASON"
            fi
        fi

        # Update stored state (using a file to store between iterations since we're in a subshell)
        echo "$STATUS|$ITEMS" > "/tmp/batch_state_${BATCH_ID}.tmp"
    done

    # Move temp files to final state directory
    for tmpfile in /tmp/batch_state_*.tmp; do
        [ -f "$tmpfile" ] || continue
        batch_id=$(basename "$tmpfile" .tmp | sed 's/batch_state_//')
        status=$(cut -d'|' -f1 "$tmpfile")
        items=$(cut -d'|' -f2 "$tmpfile")
        echo "$status|$items" > "/tmp/batch_state_${batch_id}"
        rm "$tmpfile"
    done

    sleep "$POLL_INTERVAL"
done
