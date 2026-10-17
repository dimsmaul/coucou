#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-gh-account.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    tests/GitHubTestStubs.swift \
    NotchBuddy/Sources/App/GitHubAccountManager.swift \
    tests/GitHubAccountManagerTests.swift \
    -o "$TEST_DIR/gh-account-tests"

"$TEST_DIR/gh-account-tests"
