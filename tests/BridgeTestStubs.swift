import Foundation
import CoreGraphics

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var dict: [String: String] = [:]
    func get(_ key: String) -> String? { dict[key] }
    func set(_ key: String, value: String) { dict[key] = value }
}

enum Keychain {
    static func load(key: String) -> String? { nil }
}

enum PromptContext {
    case window(app: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)
}
