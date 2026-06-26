# Batch State Monitoring Guide

This guide shows how to monitor batch state changes and watch the saga progress in real-time.

**Prerequisite:** the manual dev stack must be running with host port mappings.
Use `./scripts/dev-up.sh --build` (NOT plain `docker compose up` — that boots
the port-less base file). The scripts below hit `http://localhost:{PORT}` for
the orchestrator, Keycloak, etc., so the host bindings from
`docker-compose.dev.yml` must be active.

## Quick Start

### 1. List all batches
```bash
./scripts/list-batches.sh
```

### 2. Filter by status
```bash
./scripts/list-batches.sh PENDING_REGISTRAR
./scripts/list-batches.sh COMPLETED
./scripts/list-batches.sh FAILED
```

### 3. Watch a specific batch
```bash
# Get batch ID first
BATCH_ID=$(./scripts/list-batches.sh | grep -o '[a-f0-9-]\{36\}' | head -1)
./scripts/watch-batch.sh $BATCH_ID
```

### 4. Monitor all batches
```bash
./scripts/monitor-all-batches.sh
```

## Saga State Flow

```
DRAFT → PENDING_REGISTRAR → REGISTRAR_SIGNING → PENDING_DEAN → DEAN_SIGNING → SEALING → PDF_GENERATION → PDF_SIGNING → COMPLETED
         (human gate)         (automatic)        (human gate)    (automatic)     (auto)      (auto)          (auto)       (terminal)
```

## Status Meanings

| Status | Type | Description | Action Required |
|--------|------|-------------|-----------------|
| `DRAFT` | Initial | Batch created, items can be assigned | None (or add items) |
| `PENDING_REGISTRAR` | Human Gate | Waiting for registrar approval | **Registrar must approve** |
| `REGISTRAR_SIGNING` | Automatic | Registrar XAdES signing in progress | None (automatic) |
| `PENDING_DEAN` | Human Gate | Waiting for dean approval | **Dean must approve** |
| `DEAN_SIGNING` | Automatic | Dean XAdES signing in progress | None (automatic) |
| `SEALING` | Automatic | University seal signing (XAdES + PAdES) | None (automatic) |
| `PDF_GENERATION` | Automatic | PDF/A-3b rendering in progress | None (automatic) |
| `PDF_SIGNING` | Automatic | PDF PAdES signing in progress | None (automatic) |
| `COMPLETED` | Terminal | Full saga completed successfully | **None** |
| `CANCELLED` | Terminal | Batch was cancelled | **None** |
| `FAILED` | Terminal | Batch failed (check failureReason) | **None** |

## Direct API Access

### Get batch details
```bash
curl http://localhost:8095/api/v1/batches/{batch-id} | jq '.'
```

### List batches (up to 100)
```bash
curl http://localhost:8095/api/v1/batches | jq '.'
```

### Filter by status
```bash
curl "http://localhost:8095/api/v1/batches?status=PENDING_REGISTRAR" | jq '.'
```

### Paginated results
```bash
curl "http://localhost:8095/api/v1/batches?page=0&size=20" | jq '.'
```

## Kafka Event Monitoring

Monitor the saga events flowing through Kafka:

```bash
# Approval events
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic approval.registrar \
  --from-beginning \
  --max-messages 10

# Dean approval events
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic approval.dean \
  --from-beginning \
  --max-messages 10

# Batch completion events
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic transcript.batch.completed \
  --from-beginning \
  --max-messages 10
```

## Database Monitoring

Query the database directly for batch states:

```bash
# Connect to postgres
docker exec -it postgres psql -U postgres -d transcript_orchestrator

# List batches with status
SELECT id, name, status, item_count, created_at
FROM batches
ORDER BY created_at DESC
LIMIT 10;

# Get batch details
SELECT * FROM batches WHERE id = 'your-batch-id';

# Get transcript items for a batch
SELECT * FROM transcript_items WHERE batch_id = 'your-batch-id';
```

## Troubleshooting

### Batch stuck in PENDING_REGISTRAR
- Registrar needs to approve via the UI or publish to `approval.registrar` topic
- Check the UI at `http://localhost:8081` (login as `registrar1`)

### Batch stuck in PENDING_DEAN
- Dean needs to approve via the UI or publish to `approval.dean` topic
- Check the UI at `http://localhost:8081` (login as `dean1`)

### Batch in FAILED state
- Check `failureReason` field in batch details
- Check logs: `docker logs transcript-signing`

### Batch disappeared from list
- May have been deleted or filtered by status
- Try without status filter: `./scripts/list-batches.sh`

## Environment Variables

Configure the orchestrator URL:
```bash
export ORCHESTRATOR_URL="http://localhost:8095"
./scripts/watch-batch.sh <batch-id>
```

For remote orchestrator:
```bash
export ORCHESTRATOR_URL="http://orchestrator.example.com:8095"
./scripts/watch-batch.sh <batch-id>
```

## Examples

### Example 1: Watch a batch through completion
```bash
# List batches
./scripts/list-batches.sh

# Watch a specific batch
./scripts/watch-batch.sh 123e4567-e89b-12d3-a456-426614174000

# Output will show state transitions:
# ━━━ ➡ PENDING_REGISTRAR → REGISTRAR_SIGNING → PENDING_DEAN → DEAN_SIGNING → SEALING → PDF_GENERATION → PDF_SIGNING → COMPLETED
```

### Example 2: Monitor all batches for issues
```bash
# Monitor all batches
./scripts/monitor-all-batches.sh 10

# Look for batches stuck in human gates or failures
./scripts/list-batches.sh PENDING_REGISTRAR
./scripts/list-batches.sh PENDING_DEAN
./scripts/list-batches.sh FAILED
```

### Example 3: Debug a failed batch
```bash
# Get batch ID
FAILED_BATCH=$(./scripts/list-batches.sh FAILED | grep -o '[a-f0-9-]\{36\}' | head -1)

# Get full details
curl "http://localhost:8095/api/v1/batches/$FAILED_BATCH" | jq '.'
```

## Integration with E2E Tests

The `CrossServiceHappyPathIT` already demonstrates batch monitoring:

```java
// Gate on PENDING_DEAN before publishing dean approval
Awaitility.await("Batch reaches PENDING_DEAN after registrar approval")
    .atMost(60, TimeUnit.SECONDS)
    .until(() -> {
        BatchDetail detail = getBatchDetail(orchestratorBase, batchId);
        return "PENDING_DEAN".equals(detail.status());
    });
```

This pattern prevents publishing dean approval before the batch is ready.
