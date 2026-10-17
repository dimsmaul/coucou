import Foundation

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var dict: [String: String] = [:]
    func get(_ key: String) -> String? { dict[key] }
    func set(_ key: String, value: String) { dict[key] = value }
    func remove(_ key: String) { dict.removeValue(forKey: key) }
}

final class DemoEngine: @unchecked Sendable {
    static var isPollerPaused: Bool = false
}

@MainActor
final class AppState {
    static let shared = AppState()
    var huggingFaceUser: HuggingFaceUser? = nil
    var huggingFaceModels: [HuggingFaceModel] = []
    var huggingFaceDatasets: [HuggingFaceDataset] = []
    var huggingFaceSpaces: [HuggingFaceSpace] = []
    var huggingFaceLoaded: Bool = false
    var huggingFaceError: String? = nil
}
