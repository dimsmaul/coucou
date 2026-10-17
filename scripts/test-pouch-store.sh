#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-pouch-store.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path /tmp/swift-cache \
    NotchBuddy/Sources/App/PouchStore.swift \
    tests/PouchStoreTests.swift -o "$TEST_DIR/pouch-store-tests"
"$TEST_DIR/pouch-store-tests"
