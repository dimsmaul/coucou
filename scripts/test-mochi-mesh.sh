#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-mochi-mesh.XXXXXX")"
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
    NotchBuddy/Sources/App/LocalChat.swift \
    NotchBuddy/Sources/App/AntigravityBridge.swift \
    NotchBuddy/Sources/App/ZedBridge.swift \
    NotchBuddy/Sources/App/VSCodiumBridge.swift \
    NotchBuddy/Sources/App/EditorInspector.swift \
    NotchBuddy/Sources/App/DeviceOrchestrator.swift \
    NotchBuddy/Sources/App/DiscordService.swift \
    NotchBuddy/Sources/App/MochiMeshOrchestrator.swift \
    tests/MochiMeshTests.swift \
    -o "$TEST_DIR/mochi-mesh-tests"

"$TEST_DIR/mochi-mesh-tests"
