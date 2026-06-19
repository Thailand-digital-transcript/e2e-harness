#!/usr/bin/env bash
# Sync the dev realm from the UI repo (single source of truth) into infra/keycloak/.
set -euo pipefail
SRC="${APPROVAL_UI_DIR:-../transcript-approval-ui}/keycloak/realm-export.json"
DEST="infra/keycloak/realm-export.json"
mkdir -p "$(dirname "$DEST")"
# Filter `organizationsEnabled` — Keycloak 24.0.5 rejects the field on import
# with UnrecognizedPropertyException. The UI realm (newer Keycloak export)
# includes it for organization-support feature; the harness's 24.0.5 doesn't
# recognize it. Strip it here; the UI repo stays untouched.
jq 'del(.organizationsEnabled)' "$SRC" > "$DEST"
echo "synced realm: $SRC -> $DEST (organizationsEnabled stripped for 24.0.5 compat)"
