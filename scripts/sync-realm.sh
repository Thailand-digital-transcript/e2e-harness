#!/usr/bin/env bash
# Sync the dev realm from the UI repo (single source of truth) into infra/keycloak/.
set -euo pipefail
UI_DIR="${APPROVAL_UI_DIR:-../transcript-approval-ui}"
SRC="$UI_DIR/keycloak/realm-export.json"
FILTER="$UI_DIR/keycloak/realm-transform.jq"
DEST="infra/keycloak/realm-export.json"
mkdir -p "$(dirname "$DEST")"
# The transform (post.logout.redirect.uris "," -> "##") lives in the UI repo's
# keycloak/realm-transform.jq, shared with that repo's own transcript-keycloak
# image build so the two paths can never apply different filters. See that
# file for why the transform is needed.
#
# organizationsEnabled is NOT stripped here (it was, until this change): that
# was a Keycloak 24.0.5-only workaround. Verified empirically against the
# 26.6.3 pinned in docker-compose.yml — the realm imports fine without the
# strip.
jq -f "$FILTER" "$SRC" > "$DEST"
echo "synced realm: $SRC -> $DEST (via $FILTER)"
