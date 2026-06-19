#!/usr/bin/env bash
# Sync the dev realm from the UI repo (single source of truth) into infra/keycloak/.
set -euo pipefail
SRC="${APPROVAL_UI_DIR:-../transcript-approval-ui}/keycloak/realm-export.json"
DEST="infra/keycloak/realm-export.json"
mkdir -p "$(dirname "$DEST")"
cp "$SRC" "$DEST"
echo "synced realm: $SRC -> $DEST"
