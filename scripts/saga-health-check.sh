#!/usr/bin/env bash
set -euo pipefail

# Comprehensive saga health check
# Usage: ./scripts/saga-health-check.sh

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://localhost:8095}"
KAFKA_BROKER="${KAFKA_BROKER:-localhost:9092}"

# Source shared auth helper (Keycloak client-credentials grant).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_monitor_common.sh
source "${SCRIPT_DIR}/_monitor_common.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Saga Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check orchestrator availability
echo "🔍 Checking orchestrator..."
if auth_curl "${ORCHESTRATOR_URL}/api/v1/batches" > /dev/null 2>&1; then
    echo "  ✅ Orchestrator is available"
else
    echo "  ❌ Orchestrator is unavailable"
    echo "  Start with: docker compose up -d"
    exit 1
fi

# Get batch statistics
echo ""
echo "📊 Batch Statistics:"
RESPONSE=$(auth_curl "${ORCHESTRATOR_URL}/api/v1/batches")
TOTAL_BATCHES=$(echo "$RESPONSE" | jq 'length')

if [ "$TOTAL_BATCHES" -eq 0 ]; then
    echo "  ℹ️  No batches found"
else
    # Count by status
    echo "$RESPONSE" | jq -r '.[].status' | sort | uniq -c | sort -rn | while read -r count status; do
        case "$status" in
            PENDING_REGISTRAR)
                ICON="⏳"
                ;;
            PENDING_DEAN)
                ICON="⏳"
                ;;
            COMPLETED)
                ICON="✅"
                ;;
            FAILED)
                ICON="❌"
                ;;
            CANCELLED)
                ICON="🚫"
                ;;
            *)
                ICON="⚙️ "
                ;;
        esac
        printf "  $ICON %-3s %s\n" "$count" "$status"
    done

    echo ""
    echo "  Total: $TOTAL_BATCHES batches"

    # Check for stuck batches
    echo ""
    echo "⚠️  Batches needing attention:"

    STUCK_REGISTRAR=$(echo "$RESPONSE" | jq '[.[] | select(.status == "PENDING_REGISTRAR")] | length')
    STUCK_DEAN=$(echo "$RESPONSE" | jq '[.[] | select(.status == "PENDING_DEAN")] | length')
    FAILED=$(echo "$RESPONSE" | jq '[.[] | select(.status == "FAILED")] | length')

    if [ "$STUCK_REGISTRAR" -gt 0 ]; then
        echo "  ⏳ $STUCK_REGISTRAR batch(es) waiting for registrar approval"
        echo "$RESPONSE" | jq -r '.[] | select(.status == "PENDING_REGISTRAR") | "     - \(.id) [\(.name)]"' | head -3
    fi

    if [ "$STUCK_DEAN" -gt 0 ]; then
        echo "  ⏳ $STUCK_DEAN batch(es) waiting for dean approval"
        echo "$RESPONSE" | jq -r '.[] | select(.status == "PENDING_DEAN") | "     - \(.id) [\(.name)]"' | head -3
    fi

    if [ "$FAILED" -gt 0 ]; then
        echo "  ❌ $FAILED batch(es) failed"
        echo "$RESPONSE" | jq -r '.[] | select(.status == "FAILED") | "     - \(.id) [\(.name)]: \(.failureReason // "No reason")"' | head -3
    fi

    if [ "$STUCK_REGISTRAR" -eq 0 ] && [ "$STUCK_DEAN" -eq 0 ] && [ "$FAILED" -eq 0 ]; then
        echo "  ✅ All batches are healthy"
    fi
fi

# Check Kafka connectivity
echo ""
echo "🔍 Checking Kafka connectivity..."
if docker ps --format '{{.Names}}' | grep -qE '(^|-)kafka(-|_)?[0-9]*$'; then
    echo "  ✅ Kafka container is running"
else
    echo "  ⚠️  Kafka container not found"
fi

# Check MinIO connectivity
echo ""
echo "🔍 Checking MinIO connectivity..."
if docker ps --format '{{.Names}}' | grep -qE '(^|-)minio(-|_)?[0-9]*$'; then
    echo "  ✅ MinIO container is running"
else
    echo "  ⚠️  MinIO container not found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Health check complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  • List all batches: ./scripts/list-batches.sh"
echo "  • Watch a batch: ./scripts/watch-batch.sh <batch-id>"
echo "  • Monitor all batches: ./scripts/monitor-all-batches.sh"
echo "  • Monitor Kafka: ./scripts/monitor-kafka-events.sh"
