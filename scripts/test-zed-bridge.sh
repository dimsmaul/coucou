#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-zed-bridge.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    tests/BridgeTestStubs.swift \
    NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    NotchBuddy/Sources/App/LocalChat.swift \
    NotchBuddy/Sources/App/EditorInspector.swift \
    NotchBuddy/Sources/App/ZedBridge.swift \
    tests/ZedBridgeTests.swift \
    -o "$TEST_DIR/zed-bridge-tests"

"$TEST_DIR/zed-bridge-tests"
