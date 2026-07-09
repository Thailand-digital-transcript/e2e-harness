#!/usr/bin/env bash
# Asserts the keystore-init image writes 3 non-empty BCFKS keystores.
# Usage: ./.github/verify-image-keystore-init.sh <image-tag>
set -euo pipefail
img="${1:?usage: verify-image-keystore-init.sh <image-tag>}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

docker run --rm -e KEYSTORE_OUTPUT_DIR=/out -v "$tmp:/out" "$img"

for f in registrar.bfks dean.bfks seal.bfks; do
  [ -s "$tmp/$f" ] || { echo "FAIL: $f missing or empty"; exit 1; }
done
echo "OK: $img generated 3 non-empty BCFKS keystores"
