#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-mcp-client.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    NotchBuddy/Sources/CoucouKit/MochiWardrobe.swift \
    NotchBuddy/Sources/CoucouKit/MochiPersona.swift \
    NotchBuddy/Sources/App/MCPClient.swift \
    tests/MCPClientTests.swift \
    -o "$TEST_DIR/mcp-client-tests"

"$TEST_DIR/mcp-client-tests"
