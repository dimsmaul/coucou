import Foundation

// Minimal stubs for standalone test compilation

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var dict: [String: String] = [:]
    func get(_ key: String) -> String? { dict[key] }
    func set(_ key: String, value: String) { dict[key] = value }
}

@MainActor
final class AppState {
    static let shared = AppState()
    var githubPulse: Any? = nil
    var githubActivity: Any? = nil
    var githubStats: Any? = nil
    var showingIntegrationDetail: Bool = false
}

final class GithubPoller: @unchecked Sendable {
    static let shared = GithubPoller()
    func triggerPulseNow() {}
    func refreshActivityIfStale(maxAge: TimeInterval = 300) {}
    func refreshStats() {}
}

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()
    func play(_ name: String) {}
}
