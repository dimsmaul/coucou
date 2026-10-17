#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-hf.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    tests/HuggingFaceTestStubs.swift \
    tests/VoiceTestStubs.swift \
    tests/PillFixture.swift \
    NotchBuddy/Sources/App/HuggingFacePoller.swift \
    tests/HuggingFacePollerTests.swift \
    -o "$TEST_DIR/hf-tests"

"$TEST_DIR/hf-tests"
