#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPIKE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TEST_PACKAGE=$(mktemp -d "${TMPDIR:-/tmp}/app-routing-spike-tests.XXXXXX")
trap 'rm -rf "$TEST_PACKAGE"' EXIT HUP INT TERM

mkdir -p "$TEST_PACKAGE/Sources" "$TEST_PACKAGE/Tests"
cp "$SCRIPT_DIR/NetworkingTests.Package.swift" "$TEST_PACKAGE/Package.swift"
ln -s "$SPIKE_ROOT/Shared/SpikeContracts.swift" "$TEST_PACKAGE/Sources/SpikeContracts.swift"
for source in "$SPIKE_ROOT"/Networking/*.swift; do
  ln -s "$source" "$TEST_PACKAGE/Sources/$(basename "$source")"
done
ln -s \
  "$SPIKE_ROOT/Tests/NetworkingTests/NetworkingTests.swift" \
  "$TEST_PACKAGE/Tests/NetworkingTests.swift"

swift test --package-path "$TEST_PACKAGE"
