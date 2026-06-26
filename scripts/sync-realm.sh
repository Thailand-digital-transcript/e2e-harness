#!/usr/bin/env bash
# Sync the dev realm from the UI repo (single source of truth) into infra/keycloak/.
set -euo pipefail
SRC="${APPROVAL_UI_DIR:-../transcript-approval-ui}/keycloak/realm-export.json"
DEST="infra/keycloak/realm-export.json"
mkdir -p "$(dirname "$DEST")"
# Filter `organizationsEnabled` — the UI realm export carries it for the
# organization-support feature, which the harness's demo/IT flows don't use
# (demo users are plain realm users keyed by an institution_code attribute).
# Stripping it keeps the imported realm's behavior identical across Keycloak
# versions; the UI repo stays untouched.
jq 'del(.organizationsEnabled)' "$SRC" > "$DEST"
echo "synced realm: $SRC -> $DEST (organizationsEnabled stripped — harness doesn't use organizations)"
