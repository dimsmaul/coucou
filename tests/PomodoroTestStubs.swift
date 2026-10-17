import Foundation

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()
    var lastPlayed: String?
    func play(_ name: String) { lastPlayed = name }
}

enum IslandMode: String {
    case hidden, compact, expanded
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    var mode: IslandMode = .hidden
    var tasks: [String] = []
    func syncMode() {
        if tasks.isEmpty && mode == .compact {
            if !PomodoroManager.shared.isActive {
                mode = .hidden
            }
        } else if (!tasks.isEmpty || PomodoroManager.shared.isActive) && mode == .hidden {
            mode = .compact
        }
    }
}

enum BotEmote: String {
    case happy, proud, wink, surprised
}

extension Notification.Name {
    static let hookReveal = Notification.Name("notchBuddy.hookReveal")
    static let triggerEmote = Notification.Name("notchBuddy.triggerEmote")
    static let pomodoroStateChanged = Notification.Name("notchBuddy.pomodoroStateChanged")
}
