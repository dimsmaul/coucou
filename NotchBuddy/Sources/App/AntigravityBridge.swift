import Foundation
import AppKit

// MARK: - Antigravity / Gemini CLI Bridge Service

enum AntigravityBridge {

    /// Known paths where gemini or agy binaries are commonly located on macOS.
    private static let candidateBinaryPaths: [String] = [
        "/opt/homebrew/bin/gemini",
        "/usr/local/bin/gemini",
        "/opt/homebrew/bin/agy",
        "/usr/local/bin/agy",
    ]

    /// Resolves the executable path of the Gemini CLI or Antigravity binary.
    static func resolveBinaryPath() -> String? {
        let fileManager = FileManager.default

        // 1. Check standard system/homebrew paths
        for path in candidateBinaryPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 2. Check user's home ~/.local/bin
        let home = fileManager.homeDirectoryForCurrentUser.path
        let localBin = "\(home)/.local/bin"
        for name in ["gemini", "agy"] {
            let path = "\(localBin)/\(name)"
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. Search nvm directory for installed node binaries
        let nvmVersions = "\(home)/.nvm/versions/node"
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmVersions) {
            for v in versions.sorted().reversed() {
                let geminiPath = "\(nvmVersions)/\(v)/bin/gemini"
                if fileManager.isExecutableFile(atPath: geminiPath) {
                    return geminiPath
                }
            }
        }

        return nil
    }

    /// Resolves any stored or cached API key for Antigravity / Gemini.
    static func resolvedApiKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["ANTIGRAVITY_API_KEY"], !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !key.isEmpty {
            return key
        }
        if let key = KeychainStore.shared.get("antigravity-api-key"), !key.isEmpty {
            return key
        }
        if let key = KeychainStore.shared.get("google-api-key"), !key.isEmpty {
            return key
        }
        if let key = Keychain.load(key: "gemini-cli-api-key"), !key.isEmpty {
            return key
        }
        // Try reading from ~/.gemini/settings.json or related config files
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidatePaths = [
            ".gemini/settings.json",
            ".gemini/antigravity-cli/settings.json",
            ".gemini/antigravity/settings.json",
            ".config/gemini/settings.json",
            ".config/antigravity/settings.json"
        ]
        let candidateKeys = ["apiKey", "geminiApiKey", "GEMINI_API_KEY", "GOOGLE_API_KEY", "key"]

        for relPath in candidatePaths {
            let fileURL = home.appendingPathComponent(relPath)
            if let data = try? Data(contentsOf: fileURL),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                for k in candidateKeys {
                    if let val = json[k] as? String, !val.isEmpty {
                        return val
                    }
                }
                if let auth = json["auth"] as? [String: Any] {
                    for k in candidateKeys {
                        if let val = auth[k] as? String, !val.isEmpty {
                            return val
                        }
                    }
                }
                if let general = json["general"] as? [String: Any] {
                    for k in candidateKeys {
                        if let val = general[k] as? String, !val.isEmpty {
                            return val
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Reads the cached active Google account email from ~/.gemini/google_accounts.json if logged in.
    static func connectedGoogleAccount() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/google_accounts.json")
        guard let data = try? Data(contentsOf: path),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let active = json["active"] as? String, !active.isEmpty else {
            return nil
        }
        return active
    }

    /// Checks if OAuth credentials exist in ~/.gemini/oauth_creds.json or account cache.
    static func isOauthAuthenticated() -> Bool {
        if connectedGoogleAccount() != nil { return true }
        let credsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/oauth_creds.json")
        return FileManager.default.fileExists(atPath: credsPath.path)
    }

    /// Checks if Antigravity or Gemini CLI access is available.
    static func isAvailable() -> Bool {
        return resolvedApiKey() != nil || isOauthAuthenticated() || resolveBinaryPath() != nil
    }

    /// Launches an interactive Google / Gmail OAuth login session via the Gemini CLI.
    @MainActor
    static func loginWithGoogle(
        onStatus: @MainActor @escaping (String) -> Void,
        completion: @MainActor @escaping (Result<String, LocalChatError>) -> Void
    ) {
        guard let binary = resolveBinaryPath() else {
            completion(.failure(.serverError("Gemini CLI binary not found.")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-p", "ping", "--model", "gemini-2.5-flash"]

            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"
            env["NO_COLOR"] = "1"
            process.environment = env

            let inPipe = Pipe()
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outHandle = outPipe.fileHandleForReading
            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                if text.contains("Do you want to continue?") || text.contains("Opening authentication page") {
                    inPipe.fileHandleForWriting.write(Data("Y\n".utf8))
                    DispatchQueue.main.async {
                        onStatus("Opening browser… Complete Google sign-in in your browser.")
                    }
                }
            }

            do {
                try process.run()
                DispatchQueue.main.async {
                    onStatus("Starting Google sign-in…")
                }
                process.waitUntilExit()
                outHandle.readabilityHandler = nil

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        let email = connectedGoogleAccount() ?? "Google Account"
                        completion(.success(email))
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errText = String(data: errData, encoding: .utf8) ?? "Process exited with code \(process.terminationStatus)"
                        if errText.contains("IneligibleTierError") || errText.contains("UNSUPPORTED_CLIENT") {
                            completion(.failure(.serverError("Google has deprecated individual Gmail OAuth for the legacy Gemini CLI. Please use a free Gemini API key from Google AI Studio (aistudio.google.com/apikey).")))
                        } else {
                            completion(.failure(.serverError(errText.trimmingCharacters(in: .whitespacesAndNewlines))))
                        }
                    }
                }
            } catch {
                outHandle.readabilityHandler = nil
                DispatchQueue.main.async {
                    completion(.failure(.serverError("Failed to launch login: \(error.localizedDescription)")))
                }
            }
        }
    }

    /// Opens the Gemini CLI inside Terminal.app for interactive Google login.
    @MainActor
    static func openLoginInTerminal() {
        guard let binary = resolveBinaryPath() else { return }
        let script = """
        tell application "Terminal"
            activate
            do script "\(binary)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Available Gemini models for Antigravity access.
    static func availableModels() -> [(id: String, label: String)] {
        return [
            ("gemini-2.5-flash", "Gemini 2.5 Flash"),
            ("gemini-3.8-pro",   "Gemini 3.8 Pro"),
            ("gemini-3.8-flash", "Gemini 3.8 Flash"),
            ("gemini-2.0-flash", "Gemini 2.0 Flash"),
            ("gemini-1.5-pro",   "Gemini 1.5 Pro"),
        ]
    }

    /// Streams a chat completion using either the direct Gemini API (if key available) or the CLI subprocess.
    static func streamChat(
        query: String,
        context: PromptContext?,
        model: String,
        messages: [[String: Any]],
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        // Fast path: Direct API call if API key / token is found
        if let key = resolvedApiKey() {
            let baseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
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
                authHeader: "Bearer \(key)",
                onToken: onToken
            )
        }

        // Subprocess path: Run gemini CLI
        guard let binary = resolveBinaryPath() else {
            throw LocalChatError.serverError("Gemini CLI binary or API key not found. Ensure gemini is in PATH or configure in Settings → Chat.")
        }

        return try await runCLIProcess(binary: binary, model: model, prompt: query, onToken: onToken)
    }

    private static func runCLIProcess(
        binary: String,
        model: String,
        prompt: String,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                // Gemini CLI takes arguments or prompt string
                process.arguments = ["-p", prompt, "--model", model]

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                env["NO_COLOR"] = "1"
                process.environment = env

                let inPipe = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardInput = inPipe
                process.standardOutput = outPipe
                process.standardError = errPipe

                var accumulated = ""
                let outHandle = outPipe.fileHandleForReading

                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    if text.contains("Do you want to continue?") || text.contains("Opening authentication page") {
                        inPipe.fileHandleForWriting.write(Data("Y\n".utf8))
                        DispatchQueue.main.async {
                            onToken("Opening browser to complete Google sign-in…")
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        accumulated += text
                        onToken(accumulated)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    outHandle.readabilityHandler = nil

                    if process.terminationStatus == 0 {
                        let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                        DispatchQueue.main.async {
                            onToken(final)
                        }
                        continuation.resume(returning: final)
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errText = String(data: errData, encoding: .utf8) ?? "Process exited with status \(process.terminationStatus)"
                        if errText.contains("Please set an Auth method") || errText.contains("GEMINI_API_KEY") {
                            continuation.resume(throwing: LocalChatError.serverError("Gemini auth missing: Antigravity connects via Google OAuth, which macOS security prevents other apps from reading directly. Add \"apiKey\": \"...\" into ~/.gemini/settings.json or paste your Gemini API key in Coucou Settings → Chat."))
                        } else if errText.contains("IneligibleTierError") || errText.contains("UNSUPPORTED_CLIENT") {
                            continuation.resume(throwing: LocalChatError.serverError("Google has deprecated individual Gmail OAuth for the legacy Gemini CLI. Please use a free Gemini API key from Google AI Studio (aistudio.google.com/apikey)."))
                        } else {
                            continuation.resume(throwing: LocalChatError.serverError("Gemini CLI error: \(errText.trimmingCharacters(in: .whitespacesAndNewlines))"))
                        }
                    }
                } catch {
                    outHandle.readabilityHandler = nil
                    continuation.resume(throwing: LocalChatError.serverError("Failed to launch Gemini CLI: \(error.localizedDescription)"))
                }
            }
        }
    }
}
