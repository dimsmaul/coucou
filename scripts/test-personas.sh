#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-personas.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    tests/BridgeTestStubs.swift \
    tests/PersonaTestStubs.swift \
    NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    NotchBuddy/Sources/CoucouKit/ColorHex.swift \
    NotchBuddy/Sources/CoucouKit/MochiWardrobe.swift \
    NotchBuddy/Sources/CoucouKit/MochiPersona.swift \
    NotchBuddy/Sources/App/MCPClient.swift \
    NotchBuddy/Sources/App/PersonaStore.swift \
    tests/PersonaStoreTests.swift \
    -o "$TEST_DIR/persona-tests"

"$TEST_DIR/persona-tests"
