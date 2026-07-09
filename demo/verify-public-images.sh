#!/usr/bin/env bash
# Asserts every demo image is pullable ANONYMOUSLY from GHCR.
# Must run logged out: your own credentials would mask a private package.
set -euo pipefail
NS="ghcr.io/thailand-digital-transcript"
TAG="${1:-main}"
IMAGES=(
  transcript-processing
  transcript-orchestrator
  transcript-signing
  transcript-pdf-generation
  transcript-approval-ui
  eidasremotesigning
)

docker logout ghcr.io >/dev/null 2>&1 || true

fail=0
for img in "${IMAGES[@]}"; do
  if docker manifest inspect "$NS/$img:$TAG" >/dev/null 2>&1; then
    echo "OK   $NS/$img:$TAG"
  else
    echo "FAIL $NS/$img:$TAG — not anonymously pullable (private package?)"
    fail=1
  fi
done
exit $fail
