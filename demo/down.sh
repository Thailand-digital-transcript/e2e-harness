#!/usr/bin/env bash
# demo/down.sh — tear down the demo stack and remove volumes.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
docker compose -f docker-compose.yml -f demo/docker-compose.demo.yml down -v
echo "demo: stack stopped and volumes removed."
