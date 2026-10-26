#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-notes.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    NotchBuddy/Sources/App/NotesStore.swift \
    tests/NotesStoreTests.swift \
    -o "$TEST_DIR/notes-tests"

"$TEST_DIR/notes-tests"
