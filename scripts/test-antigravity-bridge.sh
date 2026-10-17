#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-ag-bridge.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    tests/BridgeTestStubs.swift \
    NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    NotchBuddy/Sources/App/LocalChat.swift \
    NotchBuddy/Sources/App/AntigravityBridge.swift \
    tests/AntigravityBridgeTests.swift \
    -o "$TEST_DIR/ag-bridge-tests"

"$TEST_DIR/ag-bridge-tests"
