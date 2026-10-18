import Foundation
import AppKit

// MARK: - Zed Subscription & Code Editor Bridge Service

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

    // MARK: - Code Editor Identity & Paths

    /// Standard bundle identifiers for Zed builds on macOS.
    static let bundleIdentifiers: [String] = [
        "dev.zed.Zed",
        "dev.zed.Zed-Preview"
    ]

    /// Known application paths where Zed is typically installed.
    static let candidateAppPaths: [String] = [
        "/Applications/Zed.app",
        "/Applications/Zed - Preview.app",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Zed.app",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Zed - Preview.app"
    ]

    /// Known CLI binary paths where Zed CLI is typically located.
    static let candidateBinaryPaths: [String] = [
        "/Applications/Zed.app/Contents/MacOS/cli",
        "/Applications/Zed - Preview.app/Contents/MacOS/cli",
        "/usr/local/bin/zed",
        "/opt/homebrew/bin/zed",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/zed"
    ]

    /// Checks if Zed is installed on the system (via bundle ID, app bundle, or CLI).
    static var isInstalled: Bool {
        for id in bundleIdentifiers {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
                return true
            }
        }
        for path in candidateAppPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return resolveExecutablePath() != nil
    }

    /// Checks if a Zed instance is currently running.
    static var isRunning: Bool {
        let running = NSWorkspace.shared.runningApplications
        return running.contains { app in
            guard let id = app.bundleIdentifier?.lowercased() else { return false }
            return bundleIdentifiers.contains(where: { id.contains($0.lowercased()) }) || id.contains("dev.zed")
        }
    }

    /// Resolves the URL for the installed Zed app bundle.
    static func resolveAppURL() -> URL? {
        for id in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        for path in candidateAppPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Resolves the executable path of the `zed` CLI.
    static func resolveExecutablePath() -> String? {
        let fm = FileManager.default
        for path in candidateBinaryPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Opens Zed, optionally targeting a specific workspace folder.
    @discardableResult
    static func open(workspacePath: String? = nil) -> Bool {
        let appURL = resolveAppURL()

        // 1. If a workspace/folder path is provided, open it directly in Zed
        if let path = workspacePath, !path.isEmpty {
            if let cli = resolveExecutablePath() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cli)
                process.arguments = [path]
                if (try? process.run()) != nil {
                    return true
                }
            }
            if let appURL = appURL {
                let folderURL = URL(fileURLWithPath: path)
                NSWorkspace.shared.open(
                    [folderURL],
                    withApplicationAt: appURL,
                    configuration: .init(),
                    completionHandler: nil
                )
                return true
            }
        }

        // 2. Bring existing running instance to front
        let runningApps = NSWorkspace.shared.runningApplications
        if let running = runningApps.first(where: { app in
            guard let id = app.bundleIdentifier?.lowercased() else { return false }
            return bundleIdentifiers.contains(where: { id.contains($0.lowercased()) }) || id.contains("dev.zed")
        }) {
            running.activate()
            return true
        }

        // 3. Launch fresh via NSWorkspace
        if let appURL = appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
            return true
        }

        // 4. Fallback: run CLI binary if found
        if let cli = resolveExecutablePath() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = []
            try? process.run()
            return true
        }

        return false
    }

    /// Opens a specific file in Zed, optionally navigating to line and column.
    @discardableResult
    static func openFile(path: String, line: Int? = nil, column: Int? = nil) -> Bool {
        if let cli = resolveExecutablePath() {
            let target: String
            if let line = line {
                if let column = column {
                    target = "\(path):\(line):\(column)"
                } else {
                    target = "\(path):\(line)"
                }
            } else {
                target = path
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = [target]
            if (try? process.run()) != nil {
                return true
            }
        }

        if let appURL = resolveAppURL() {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: path)],
                withApplicationAt: appURL,
                configuration: .init(),
                completionHandler: nil
            )
            return true
        }
        return false
    }

    /// Queries recently opened workspaces from Zed's local SQLite database.
    static func recentWorkspaces() -> [String] {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zed/db/0-stable/db.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [dbPath, "SELECT paths FROM workspaces ORDER BY timestamp DESC LIMIT 10;"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var results: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !results.contains(trimmed) {
                results.append(trimmed)
            }
        }
        return results
    }

    /// Checks if Zed is installed or settings exist.
    static func isZedDetected() -> Bool {
        isInstalled || FileManager.default.fileExists(atPath: zedSettingsURL.path)
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
