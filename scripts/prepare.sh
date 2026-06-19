#!/usr/bin/env bash
# One-shot pre-`docker compose` / pre-`mvn verify` step: keystores, service jars, realm.
set -euo pipefail
./scripts/gen-keystores.sh
./scripts/build-jars.sh
./scripts/sync-realm.sh
echo "prepare complete"
