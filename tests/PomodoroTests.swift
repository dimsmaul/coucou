import Foundation

@MainActor
func runPomodoroTests() {
    print("--- Starting PomodoroManager Tests ---")

    let manager = PomodoroManager.shared

    // Test 1: Initial state
    assert(manager.state == .idle, "Initial state should be idle")
    assert(!manager.isActive, "Initial state should not be active")
    assert(manager.mode == .pomodoro, "Initial mode should be pomodoro")
    print("✓ Test 1: Initial state passed")

    // Test 2: Start Focus (25m)
    manager.startFocus(minutes: 25)
    assert(manager.state == .running, "State should be running")
    assert(manager.isActive, "Should be active")
    assert(manager.totalDuration == 25 * 60, "Duration should be 1500s")
    assert(manager.timeRemaining > 24 * 60, "Time remaining should be ~25m")
    assert(manager.displayTime == "25:00", "Display time should format to 25:00 (got: \(manager.displayTime))")
    assert(manager.compactDisplay == "25:00", "Compact display should be '25:00' (got: \(manager.compactDisplay))")
    assert(SoundEngine.shared.lastPlayed == "pop", "Should play pop sound on start")
    print("✓ Test 2: Start Focus passed")

    // Test 3: Pause and Resume
    manager.pause()
    assert(manager.state == .paused, "State should be paused")
    assert(manager.isActive, "Should still be active while paused")
    assert(manager.compactDisplay.contains("⏸"), "Compact display should show pause indicator (got: \(manager.compactDisplay))")
    assert(SoundEngine.shared.lastPlayed == "blip", "Should play blip sound on pause")

    manager.resume()
    assert(manager.state == .running, "State should be running after resume")
    assert(SoundEngine.shared.lastPlayed == "blip", "Should play blip sound on resume")
    print("✓ Test 3: Pause & Resume passed")

    // Test 4: Toggle pause
    manager.togglePause()
    assert(manager.state == .paused, "Should pause on toggle")
    manager.togglePause()
    assert(manager.state == .running, "Should resume on toggle")
    print("✓ Test 4: Toggle Pause passed")

    // Test 5: Add Minutes (+5m)
    let prevDuration = manager.totalDuration
    manager.addMinutes(5)
    assert(manager.totalDuration == prevDuration + 5 * 60, "Duration should increase by 300s")
    assert(manager.timeRemaining > 29 * 60, "Remaining time should increase by ~5m")
    assert(SoundEngine.shared.lastPlayed == "pop", "Should play pop sound on add time")
    print("✓ Test 5: Add Minutes passed")

    // Test 6: Reset
    manager.reset()
    assert(manager.state == .idle, "State should be idle after reset")
    assert(!manager.isActive, "Should not be active after reset")
    assert(SoundEngine.shared.lastPlayed == "close", "Should play close sound on reset")
    print("✓ Test 6: Reset passed")

    // Test 7: Presets (Short Break & Long Break)
    manager.startShortBreak(minutes: 5)
    assert(manager.mode == .shortBreak, "Mode should be shortBreak")
    assert(manager.totalDuration == 5 * 60, "Duration should be 300s")
    assert(manager.compactDisplay == "05:00", "Compact display should show 05:00 (got: \(manager.compactDisplay))")

    manager.startLongBreak(minutes: 15)
    assert(manager.mode == .longBreak, "Mode should be longBreak")
    assert(manager.totalDuration == 15 * 60, "Duration should be 900s")
    assert(manager.compactDisplay == "15:00", "Compact display should show 15:00 (got: \(manager.compactDisplay))")
    print("✓ Test 7: Presets (Short & Long Break) passed")

    // Test 8: Time Tracker (Count-up)
    manager.startTracker()
    assert(manager.mode == .tracker, "Mode should be tracker")
    assert(!manager.isCountdown, "Tracker should not be countdown")
    assert(manager.state == .running, "Tracker should be running")
    assert(manager.compactDisplay == "00:00", "Compact display should be 00:00 (got: \(manager.compactDisplay))")
    print("✓ Test 8: Time Tracker passed")

    // Test 9: AppState syncMode integration
    AppState.shared.tasks = []
    AppState.shared.mode = .compact
    // Since manager is active (from Test 8), syncMode should KEEP compact mode!
    AppState.shared.syncMode()
    assert(AppState.shared.mode == .compact, "AppState should keep .compact mode while timer is active")

    // After reset, syncMode should allow .hidden when tasks are empty
    manager.reset()
    AppState.shared.syncMode()
    assert(AppState.shared.mode == .hidden, "AppState should become .hidden after timer reset when tasks are empty")
    print("✓ Test 9: AppState syncMode integration passed")

    // Test 10: Manual duration input & adjustMinutes
    manager.setMinutes(45)
    assert(manager.manualMinutesText == "45", "manualMinutesText should be 45")
    assert(!manager.isStopwatchConfigured, "Should not be stopwatch configured when 45m")
    manager.adjustMinutes(by: 5)
    assert(manager.manualMinutesText == "50", "Should be 50 after +5")
    manager.adjustMinutes(by: -15)
    assert(manager.manualMinutesText == "35", "Should be 35 after -15")
    manager.startConfiguredTimer()
    assert(manager.state == .running, "Should be running")
    assert(manager.mode == .pomodoro, "Should be pomodoro mode")
    assert(manager.totalDuration == 35 * 60, "Duration should be 35m")
    manager.reset()
    print("✓ Test 10: Manual duration input passed")

    // Test 11: Empty / 0 input acts as stopwatch timer
    manager.setMinutes(0)
    assert(manager.isStopwatchConfigured, "0 minutes should configure stopwatch")
    assert(manager.manualMinutesText == "", "manualMinutesText should be empty for stopwatch")
    manager.startConfiguredTimer()
    assert(manager.state == .running, "Should be running")
    assert(manager.mode == .tracker, "Empty duration should start tracker (stopwatch)")
    assert(!manager.isCountdown, "Should be count-up stopwatch")
    manager.reset()
    print("✓ Test 11: Stopwatch fallback passed")

    print("--- ALL POMODORO TESTS PASSED ---")
}

@main
struct PomodoroTestRunner {
    @MainActor
    static func main() {
        runPomodoroTests()
    }
}

