import Foundation
import SwiftUI
import AppKit

// MARK: - Pomodoro Mode & State

enum PomodoroMode: String, CaseIterable, Sendable {
    case pomodoro
    case shortBreak
    case longBreak
    case tracker

    var title: String {
        switch self {
        case .pomodoro: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        case .tracker: return "Time Tracker"
        }
    }

    var systemIcon: String {
        switch self {
        case .pomodoro: return "timer"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "pause"
        case .tracker: return "stopwatch"
        }
    }
}

enum PomodoroState: String, Sendable {
    case idle
    case running
    case paused
    case completed
}

// MARK: - Pomodoro Manager

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published var mode: PomodoroMode = .pomodoro
    @Published var state: PomodoroState = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var timeElapsed: TimeInterval = 0
    @Published var totalDuration: TimeInterval = 25 * 60
    @Published var completedSessions: Int = 0
    @Published var isMenuOpen: Bool = false
    @Published var manualMinutesText: String = "25"

    private var timer: Timer?
    private var targetEndDate: Date?
    private var trackerStartDate: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var pausedAt: Date?

    private let sessionsKey = "coucou.pomodoro.completedSessions"
    private let sessionsDateKey = "coucou.pomodoro.completedDate"

    var isStopwatchConfigured: Bool {
        let trimmed = manualMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return (Int(trimmed) ?? 0) <= 0
    }

    var configuredMinutes: Int {
        let trimmed = manualMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        return max(1, Int(trimmed) ?? 25)
    }

    var modeTitleSubtitle: String {
        switch mode {
        case .pomodoro:
            let mins = max(1, Int(ceil(totalDuration / 60)))
            return "\(mins)m Focus Session"
        case .shortBreak:
            return "Short Break"
        case .longBreak:
            return "Long Break"
        case .tracker:
            return "Stopwatch Tracker"
        }
    }

    var isActive: Bool {
        state == .running || state == .paused || state == .completed
    }

    var isCountdown: Bool {
        mode != .tracker
    }

    var displayTime: String {
        if isCountdown {
            let totalSec = max(0, Int(ceil(timeRemaining)))
            let mins = totalSec / 60
            let secs = totalSec % 60
            return String(format: "%02d:%02d", mins, secs)
        } else {
            let totalSec = max(0, Int(timeElapsed))
            let hours = totalSec / 3600
            let mins = (totalSec % 3600) / 60
            let secs = totalSec % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, mins, secs)
            } else {
                return String(format: "%02d:%02d", mins, secs)
            }
        }
    }

    var compactDisplay: String {
        switch state {
        case .completed:
            return "Done"
        case .paused:
            return "⏸ \(displayTime)"
        default:
            return displayTime
        }
    }

    var progress: Double {
        if isCountdown {
            guard totalDuration > 0 else { return 0 }
            return min(1.0, max(0.0, 1.0 - (timeRemaining / totalDuration)))
        } else {
            return 1.0
        }
    }

    private init() {
        loadSessionCount()
    }

    // MARK: - Presets & Controls

    func setMinutes(_ mins: Int) {
        if mins <= 0 {
            manualMinutesText = ""
        } else {
            manualMinutesText = "\(mins)"
        }
    }

    func adjustMinutes(by delta: Int) {
        let trimmed = manualMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = Int(trimmed) ?? (delta > 0 ? 0 : 5)
        let updated = max(0, min(180, current + delta))
        setMinutes(updated)
    }

    func startConfiguredTimer() {
        let trimmed = manualMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mins = Int(trimmed) ?? 0
        if mins > 0 {
            startFocus(minutes: mins)
        } else {
            startTracker()
        }
        isMenuOpen = false
    }

    func startFocus(minutes: Int = 25) {
        manualMinutesText = "\(minutes)"
        startCountdown(mode: .pomodoro, minutes: minutes)
    }

    func startShortBreak(minutes: Int = 5) {
        startCountdown(mode: .shortBreak, minutes: minutes)
    }

    func startLongBreak(minutes: Int = 15) {
        startCountdown(mode: .longBreak, minutes: minutes)
    }

    func startTracker() {
        manualMinutesText = ""
        timer?.invalidate()
        mode = .tracker
        totalDuration = 0
        timeElapsed = 0
        accumulatedElapsed = 0
        timeRemaining = 0
        trackerStartDate = Date()
        state = .running
        SoundEngine.shared.play("pop")
        startTickTimer()
        revealCompactIfNeeded()
    }

    private func startCountdown(mode: PomodoroMode, minutes: Int) {
        timer?.invalidate()
        self.mode = mode
        self.totalDuration = TimeInterval(minutes * 60)
        self.timeRemaining = self.totalDuration
        self.timeElapsed = 0
        self.targetEndDate = Date().addingTimeInterval(self.totalDuration)
        self.state = .running
        SoundEngine.shared.play("pop")
        startTickTimer()
        revealCompactIfNeeded()
    }

    func pause() {
        guard state == .running else { return }
        timer?.invalidate()
        timer = nil
        pausedAt = Date()
        if mode == .tracker, let start = trackerStartDate {
            accumulatedElapsed += pausedAt?.timeIntervalSince(start) ?? 0
            timeElapsed = accumulatedElapsed
        }
        state = .paused
        SoundEngine.shared.play("blip")
    }

    func resume() {
        guard state == .paused else { return }
        if isCountdown {
            targetEndDate = Date().addingTimeInterval(timeRemaining)
        } else {
            trackerStartDate = Date()
        }
        state = .running
        SoundEngine.shared.play("blip")
        startTickTimer()
    }

    func togglePause() {
        if state == .running {
            pause()
        } else if state == .paused {
            resume()
        }
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        targetEndDate = nil
        trackerStartDate = nil
        accumulatedElapsed = 0
        pausedAt = nil
        state = .idle
        timeRemaining = totalDuration
        timeElapsed = 0
        SoundEngine.shared.play("close")
        AppState.shared.syncMode()
        NotificationCenter.default.post(name: .pomodoroStateChanged, object: nil)
    }

    func addMinutes(_ minutes: Int) {
        let additionalSec = TimeInterval(minutes * 60)
        if isCountdown {
            totalDuration += additionalSec
            timeRemaining += additionalSec
            if state == .running {
                targetEndDate = Date().addingTimeInterval(timeRemaining)
            }
        }
        SoundEngine.shared.play("pop")
    }

    // MARK: - Timer Tick

    private func startTickTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func tick() {
        guard state == .running else { return }

        if isCountdown {
            guard let target = targetEndDate else { return }
            let remaining = target.timeIntervalSinceNow
            if remaining <= 0 {
                completeCountdown()
            } else {
                timeRemaining = remaining
                timeElapsed = totalDuration - remaining
            }
        } else {
            guard let start = trackerStartDate else { return }
            timeElapsed = accumulatedElapsed + Date().timeIntervalSince(start)
        }
    }

    private func completeCountdown() {
        timer?.invalidate()
        timer = nil
        targetEndDate = nil
        state = .completed
        timeRemaining = 0
        timeElapsed = totalDuration

        if mode == .pomodoro {
            completedSessions += 1
            saveSessionCount()
        }

        SoundEngine.shared.play("finish")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        NotificationCenter.default.post(name: .pomodoroStateChanged, object: nil)
    }

    private func revealCompactIfNeeded() {
        if AppState.shared.mode == .hidden {
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
        NotificationCenter.default.post(name: .pomodoroStateChanged, object: nil)
    }

    // MARK: - Persistence

    private func loadSessionCount() {
        let savedDate = UserDefaults.standard.object(forKey: sessionsDateKey) as? Date ?? .distantPast
        if Calendar.current.isDateInToday(savedDate) {
            completedSessions = UserDefaults.standard.integer(forKey: sessionsKey)
        } else {
            completedSessions = 0
        }
    }

    private func saveSessionCount() {
        UserDefaults.standard.set(completedSessions, forKey: sessionsKey)
        UserDefaults.standard.set(Date(), forKey: sessionsDateKey)
    }
}
