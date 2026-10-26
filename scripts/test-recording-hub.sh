#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-record-hub.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -module-cache-path /tmp/swift-cache \
    tests/RecordHubTestStubs.swift \
    NotchBuddy/Sources/CoucouKit/IslandScreenGeometry.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    NotchBuddy/Sources/App/MeetingDetector.swift \
    NotchBuddy/Sources/App/ScreenRecorder.swift \
    tests/MeetingDetectorTests.swift \
    -o "$TEST_DIR/record-hub-tests"

"$TEST_DIR/record-hub-tests"
