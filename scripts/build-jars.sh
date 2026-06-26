#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
PARENT="$(cd "$ROOT/.." && pwd)"

build() {
    local svc="$1" jar_pattern="$2" dest_dir="$3"
    echo "Building $svc..."
    # -Dmaven.test.skip=true skips both test compile and test execution.
    # Some sibling service test sources have pre-existing compile errors
    # (out of scope for the e2e-harness task); skipping test compilation
    # produces the same -exec.jar while avoiding unrelated failures.
    (cd "$dest_dir" && mvn package -Dmaven.test.skip=true -q)
    cp "$dest_dir/target/"$jar_pattern "$ROOT/services/$svc/app.jar"
    echo "  → services/$svc/app.jar"
}

build "transcript-processing"   "transcript-processing-*-exec.jar"   "$PARENT/transcript-processing"
build "transcript-orchestrator" "transcript-orchestrator-*-exec.jar" "$PARENT/transcript-orchestrator"
build "transcript-signing"      "transcript-signing-*-exec.jar"      "$PARENT/transcript-signing"
build "transcript-pdf-generation" "transcript-pdf-generation-*-exec.jar" "$PARENT/transcript-pdf-generation"

echo "Building eidasremotesigning..."
CSC_DIR="$(cd "$PARENT/../etax/eidasremotesigning" && pwd)"
(cd "$CSC_DIR" && mvn package -Dmaven.test.skip=true -q)
cp "$CSC_DIR/target/"eidasremotesigning-*.jar "$ROOT/services/eidasremotesigning/app.jar"
echo "  → services/eidasremotesigning/app.jar"

echo ""
echo "All JARs ready. For manual dev: ./scripts/dev-up.sh --build"
echo "                    For IT:        mvn verify"
