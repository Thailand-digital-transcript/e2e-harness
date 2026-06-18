#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."

cd "$ROOT"
mvn test-compile exec:java \
    -Dexec.mainClass=com.wpanther.transcript.e2e.KeystoreGenerator \
    -Dexec.classpathScope=test \
    -q
echo "Keystores ready in $ROOT/infra/csc/keystores/"
