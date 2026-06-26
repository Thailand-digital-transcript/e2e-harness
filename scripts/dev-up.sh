#!/usr/bin/env bash
set -euo pipefail

# Start the manual dev stack with host port mappings.
# Usage: ./scripts/dev-up.sh [--build]
#
# Wraps `docker compose -f docker-compose.yml -f docker-compose.dev.yml up`.
# The base docker-compose.yml is intentionally port-less so the same stack
# can boot under Testcontainers (CrossServiceHappyPathIT) without colliding
# with a manual dev session. This wrapper re-adds the host bindings for
# browser-based UI testing (http://localhost:8081) and the host-side
# monitoring scripts (./scripts/list-batches.sh, etc.).

cd "$(dirname "${BASH_SOURCE[0]}")/.."

exec docker compose -f docker-compose.yml -f docker-compose.dev.yml up "$@"