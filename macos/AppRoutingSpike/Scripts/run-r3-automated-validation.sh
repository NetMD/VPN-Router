#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPIKE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT=${1:-"$SPIKE_ROOT/DerivedData-r3/r3-automated-summary.json"}
passed=0
failed=0

run_check() {
  if "$@" >/dev/null; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
}

cd "$SPIKE_ROOT"
run_check xcodegen generate
run_check "$SCRIPT_DIR/run-networking-tests.sh"
run_check xcodebuild -project AppRoutingSpike.xcodeproj -scheme AppRoutingSpikeHost -derivedDataPath DerivedData-r3 CODE_SIGNING_ALLOWED=NO test
run_check xcodebuild -project AppRoutingSpike.xcodeproj -scheme AppRoutingSpikeSelectedTrafficHarness -derivedDataPath DerivedData-r3 CODE_SIGNING_ALLOWED=NO build
run_check xcodebuild -project AppRoutingSpike.xcodeproj -scheme AppRoutingSpikeControlTrafficHarness -derivedDataPath DerivedData-r3 CODE_SIGNING_ALLOWED=NO build
run_check "$SCRIPT_DIR/verify-generated-plists.sh" "$SPIKE_ROOT/DerivedData-r3/Build/Products/Debug"
run_check "$SCRIPT_DIR/test-generated-plists.sh"
run_check "$SCRIPT_DIR/verify-source-safety.sh"
run_check "$SCRIPT_DIR/verify-isolation.sh"
run_check "$SCRIPT_DIR/test-isolation.sh"
verdict=PASS
[ "$failed" -eq 0 ] || verdict=FAIL
mkdir -p "$(dirname -- "$OUTPUT")"
printf '{"validationAxis":"automated","validationVerdict":"%s","executedCount":%s,"passedCount":%s,"failedCount":%s,"observedAt":"%s"}\n' \
  "$verdict" "$((passed + failed))" "$passed" "$failed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUTPUT"
[ "$failed" -eq 0 ]
