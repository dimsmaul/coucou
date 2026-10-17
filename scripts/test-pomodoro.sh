#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-pomodoro.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    tests/PomodoroTestStubs.swift \
    NotchBuddy/Sources/App/PomodoroManager.swift \
    tests/PomodoroTests.swift \
    -o "$TEST_DIR/pomodoro-tests"

"$TEST_DIR/pomodoro-tests"
