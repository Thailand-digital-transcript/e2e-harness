#!/usr/bin/env bash
# demo/up.sh — bring up the interactive demo stack and seed the approval queue.
# Run from anywhere; cds to the repo root so compose relative paths resolve.
# Requires the one-time ./scripts/prepare.sh artifacts to be present.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
COMPOSE=(docker compose -f docker-compose.yml -f demo/docker-compose.demo.yml)

# ── Guard: `docker compose wait` (used below) needs Compose v2.20+ ─────────────
cv="$(docker compose version --short 2>/dev/null | sed 's/^v//')"
if ! printf '%s\n' "$cv" | awk -F. '{ exit !($1>2 || ($1==2 && $2>=20)) }'; then
  echo "demo: docker compose v2.20+ required (found ${cv:-unknown})." >&2
  exit 1
fi

# ── Guard: prepare artifacts must exist or the stack will fail to build/boot ───
missing=""
for jar in services/transcript-processing/app.jar \
           services/transcript-orchestrator/app.jar \
           services/transcript-signing/app.jar \
           services/transcript-pdf-generation/app.jar \
           services/eidasremotesigning/app.jar; do
  [ -f "$jar" ] || missing="$missing $jar"
done
[ -f infra/keycloak/realm-export.json ] || missing="$missing infra/keycloak/realm-export.json"
{ [ -d infra/csc/keystores ] && [ -n "$(ls -A infra/csc/keystores 2>/dev/null)" ]; } \
  || missing="$missing infra/csc/keystores/"
if [ -n "$missing" ]; then
  echo "demo: missing prepare artifacts:$missing" >&2
  echo "demo: run ./scripts/prepare.sh first." >&2
  exit 1
fi

echo "demo: building and starting the stack (a few minutes on a cold start)…"
"${COMPOSE[@]}" up -d --build

echo "demo: waiting for the seed job to finish…"
if ! "${COMPOSE[@]}" wait demo-seed; then
  echo "demo: seed FAILED — logs follow:" >&2
  "${COMPOSE[@]}" logs demo-seed >&2
  exit 1
fi

echo "demo: ready."
echo "demo:   Approval UI   → http://localhost:8081  (registrar1 / dean1)"
echo "demo:   MinIO console → http://localhost:9001  (minioadmin / minioadmin)"
echo "demo:   Keycloak admin→ http://localhost:8080  (admin / admin)"
