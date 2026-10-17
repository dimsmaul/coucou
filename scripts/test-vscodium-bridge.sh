#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-vscodium-bridge.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    NotchBuddy/Sources/App/VSCodiumBridge.swift \
    tests/VSCodiumBridgeTests.swift \
    -o "$TEST_DIR/vscodium-bridge-tests"

"$TEST_DIR/vscodium-bridge-tests"
