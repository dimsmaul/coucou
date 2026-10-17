import Foundation

// MARK: - Zed Subscription Bridge Service

enum ZedBridge {

    /// Default fallback models when Zed config is absent or has no zed.dev models.
    static let defaultModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6",     "Claude 3.7 Sonnet (4.6)"),
        ("gemini-3.1-pro-preview", "Gemini 3.1 Pro Preview"),
        ("claude-sonnet-4-5",     "Claude 3.5 Sonnet (4.5)"),
        ("gpt-4o",                "GPT-4o"),
    ]

    /// Path to Zed's user settings JSON file.
    static var zedSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/zed/settings.json")
    }

    /// Reads favorite and default models configured for zed.dev from Zed's settings.json.
    static func availableModels() -> [(id: String, label: String)] {
        guard let data = try? Data(contentsOf: zedSettingsURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let agent = json["agent"] as? [String: Any] else {
            return defaultModels
        }

        var models: [(id: String, label: String)] = []
        var seen = Set<String>()

        // 1. Check default model
        if let defaultModel = agent["default_model"] as? [String: Any],
           (defaultModel["provider"] as? String) == "zed.dev",
           let modelId = defaultModel["model"] as? String {
            models.append((id: modelId, label: label(for: modelId)))
            seen.insert(modelId)
        }

        // 2. Check favorite models
        if let favorites = agent["favorite_models"] as? [[String: Any]] {
            for entry in favorites {
                if (entry["provider"] as? String) == "zed.dev",
                   let modelId = entry["model"] as? String,
                   !seen.contains(modelId) {
                    models.append((id: modelId, label: label(for: modelId)))
                    seen.insert(modelId)
                }
            }
        }

        return models.isEmpty ? defaultModels : models
    }

    /// Formats a clean human-readable label for common Zed models.
    private static func label(for modelId: String) -> String {
        switch modelId {
        case "claude-sonnet-4-6":      return "Claude 3.7 Sonnet (4.6)"
        case "claude-sonnet-4-5":      return "Claude 3.5 Sonnet (4.5)"
        case "gemini-3.1-pro-preview":  return "Gemini 3.1 Pro Preview"
        case "gpt-4o":                 return "GPT-4o"
        default:                       return modelId
        }
    }

    /// Resolves the Zed Cloud authentication token from Keychain or Coucou settings.
    static func resolvedToken() -> String? {
        if let token = ProcessInfo.processInfo.environment["ZED_TOKEN"], !token.isEmpty {
            return token
        }
        // 1. Coucou's saved zed-token
        if let token = KeychainStore.shared.get("zed-token"), !token.isEmpty {
            return token
        }
        // 2. System keychain under Zed service
        if let token = Keychain.load(key: "dev.zed.Zed"), !token.isEmpty {
            return token
        }
        if let token = Keychain.load(key: "Zed"), !token.isEmpty {
            return token
        }
        return nil
    }

    /// Checks if Zed is installed or settings exist.
    static func isZedDetected() -> Bool {
        let appExists = FileManager.default.fileExists(atPath: "/Applications/Zed.app")
        let configExists = FileManager.default.fileExists(atPath: zedSettingsURL.path)
        return appExists || configExists
    }

    /// Streams a chat completion through Zed's LLM proxy endpoint using the active Zed token.
    static func streamChat(
        query: String,
        context: PromptContext?,
        model: String,
        messages: [[String: Any]],
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        guard let token = resolvedToken() else {
            throw LocalChatError.serverError("Zed subscription token missing. Configure it in Settings → Chat.")
        }

        let baseURL = "https://llm.zed.dev"
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "max_tokens": 4096,
        ]
        let encodedBody = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()

        return try await LocalChat.streamChat(
            baseURL: baseURL,
            encodedBody: encodedBody,
            model: model,
            authHeader: "Bearer \(token)",
            extraHeaders: [
                "HTTP-Referer": "https://zed.dev",
                "X-Title": "Coucou",
            ],
            onToken: onToken
        )
    }
}
