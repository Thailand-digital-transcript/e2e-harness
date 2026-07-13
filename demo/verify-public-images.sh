#!/usr/bin/env bash
# Asserts every GHCR image referenced by demo/docker-compose.public.yml is
# pullable ANONYMOUSLY. Must run logged out: your own credentials would mask a
# private package.
#
# The default tag is the one docker-compose.public.yml actually pins, so a bare
# run verifies what a public user really pulls. Pass a tag to check another
# (e.g. `./demo/verify-public-images.sh main` before cutting a release).
#
# The IMAGES list must stay in sync with the ghcr.io images in
# docker-compose.public.yml — the check below enforces that.
set -euo pipefail
NS="ghcr.io/thailand-digital-transcript"
TAG="${1:-v0.1.0}"
COMPOSE="$(dirname "$0")/docker-compose.public.yml"
IMAGES=(
  transcript-processing
  transcript-orchestrator
  transcript-signing
  transcript-pdf-generation
  transcript-approval-ui
  transcript-keycloak
  keystore-init
  eidasremotesigning
)

# Drift guard: every ghcr.io image in the compose file must appear in IMAGES.
missing_from_list=0
while read -r img; do
  case " ${IMAGES[*]} " in
    *" $img "*) ;;
    *) echo "FAIL $img is in $(basename "$COMPOSE") but not in this script's IMAGES list"
       missing_from_list=1 ;;
  esac
done < <(grep -oE "image: $NS/[a-z0-9-]+" "$COMPOSE" | sed "s|image: $NS/||" | sort -u)
[ "$missing_from_list" -eq 0 ] || exit 1

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
