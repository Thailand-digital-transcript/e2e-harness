#!/usr/bin/env bash
# demo/ingest.sh [path/to/Transcript.xml] — seed another batch into the queue.
# No arg → re-ingests the bundled fixture. File arg → ingests that XML.
# Reuses the demo-seed container in-network (no host curl/jq needed). The batch is
# always created under institution 01110 (see demo/seed.sh), so it stays visible to
# registrar1 / dean1 regardless of the XML's own institution.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
COMPOSE=(docker compose -f docker-compose.yml -f demo/docker-compose.demo.yml)

# Refuse if the stack is not already up — otherwise `compose run` would pull up the
# whole 13-container stack just to ingest one batch. Start it with ./demo/up.sh first.
if ! "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx 'transcript-orchestrator'; then
  echo "demo: stack is not running — start it with ./demo/up.sh first." >&2
  exit 1
fi

if [ "${1:-}" = "" ]; then
  echo "demo: ingesting the bundled fixture…"
  "${COMPOSE[@]}" run --rm demo-seed
else
  file="$1"
  [ -f "$file" ] || { echo "demo: file not found: $file" >&2; exit 1; }
  abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  echo "demo: ingesting $abs…"
  "${COMPOSE[@]}" run --rm -v "$abs:/fixtures/input.xml:ro" demo-seed
fi
