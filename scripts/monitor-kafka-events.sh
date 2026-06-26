#!/usr/bin/env bash
set -euo pipefail

# Monitor Kafka events for saga state changes
# Usage: ./scripts/monitor-kafka-events.sh [topic] [max-messages]

TOPIC="${1:-transcript.batch.completed}"
MAX_MESSAGES="${2:-10}"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-}"

echo "Monitoring Kafka topic: $TOPIC"
echo "Max messages: $MAX_MESSAGES"
echo ""

# Find kafka container if not specified
if [ -z "$KAFKA_CONTAINER" ]; then
    for container in kafka-1 kafka_1 kafka; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            KAFKA_CONTAINER="$container"
            break
        fi
    done
fi

if [ -z "$KAFKA_CONTAINER" ]; then
    echo "Error: Kafka container not found. Is the stack running?"
    echo "Start with: docker compose up -d"
    exit 1
fi

echo "Using Kafka container: $KAFKA_CONTAINER"
echo "Press Ctrl+C to stop"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

docker exec -it "$KAFKA_CONTAINER" kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --max-messages "$MAX_MESSAGES" \
    --property print.key=true \
    --property key.separator=" | "
