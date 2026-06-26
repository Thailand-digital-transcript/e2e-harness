#!/usr/bin/env bash
# Sync the dev realm from the UI repo (single source of truth) into infra/keycloak/.
set -euo pipefail
SRC="${APPROVAL_UI_DIR:-../transcript-approval-ui}/keycloak/realm-export.json"
DEST="infra/keycloak/realm-export.json"
mkdir -p "$(dirname "$DEST")"
# Two fix-ups are applied during the copy; the UI repo stays untouched:
#
# 1. Strip `organizationsEnabled` — the UI realm export carries it for the
#    organization-support feature, which the harness's demo/IT flows don't use
#    (demo users are plain realm users keyed by an institution_code attribute).
#
# 2. Normalize the `post.logout.redirect.uris` separator from "," to "##".
#    Keycloak stores multivalued client attributes as a `##`-separated string,
#    so a comma-joined value is parsed as one giant URI that matches nothing —
#    every RP-initiated logout then fails with "Invalid redirect uri". The UI
#    source realm uses commas; rewrite them to `##` so logout actually works.
jq 'del(.organizationsEnabled)
  | .clients |= map(
      if .attributes and .attributes["post.logout.redirect.uris"]
      then .attributes["post.logout.redirect.uris"] |= gsub(",";"##")
      else . end)' "$SRC" > "$DEST"
echo "synced realm: $SRC -> $DEST (organizationsEnabled stripped; post-logout URIs joined with ##)"
