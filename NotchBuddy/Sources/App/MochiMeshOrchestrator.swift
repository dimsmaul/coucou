import Foundation
import AppKit

// MARK: - Mochi Delegation Model

struct MochiDelegation: Equatable, Sendable {
    var targetPersonaQuery: String
    var task: String
    var projectPath: String?
}

// MARK: - Mochi Mesh Orchestrator

@MainActor
enum MochiMeshOrchestrator {

    // MARK: - Prompt Injection

    /// Generates the collaboration team prompt informing the active persona about their connected teammates.
    static func makeMeshPrompt(for persona: MochiPersona, allPersonas: [MochiPersona]) -> String {
        guard persona.connections.canDelegate else { return "" }

        let allowedIds = Set(persona.connections.connectedPersonaIds)
        let teammates = allPersonas.filter { candidate in
            guard candidate.id != persona.id else { return false }
            return allowedIds.isEmpty || allowedIds.contains(candidate.id)
        }

        guard !teammates.isEmpty else { return "" }

        var lines: [String] = [
            "---",
            "### Mochi Mesh Team Collaboration",
            "You are connected with the following specialist Mochi teammates:",
        ]

        for mate in teammates {
            var capabilities: [String] = []
            if mate.hasTerminalSkill {
                capabilities.append("runs Claude Code / CLI in terminal")
            }
            if mate.hasTunnelSkill {
                capabilities.append("deploys Cloudflare preview tunnels")
            }
            if mate.hasDockerSkill {
                capabilities.append("Docker containers")
            }
            if mate.hasVercelSkill {
                capabilities.append("Vercel deployment")
            }
            if mate.connections.canDelegate {
                capabilities.append("coordinates subtasks")
            }
            let capStr = capabilities.isEmpty ? "" : " (Skills: \(capabilities.joined(separator: ", ")))"
            lines.append("• **\(mate.name)** (ID: `\(mate.id)`): \(mate.role)\(capStr)")
        }

        lines.append("""
        When your task requires specialized assistance (e.g. codebase audit, frontend code, backend APIs, or tunnels), \
        delegate to a teammate by including this exact tag in your response:
        `@delegate(to: "<id_or_name>", task: "<detailed instruction>", project: "<optional_project_path>")`

        Example:
        `@delegate(to: "persona_analyst", task: "Analyze authentication flow and identify bugs", project: "~/Projects/eularix")`
        ---
        """)

        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing Delegations

    /// Parses `@delegate(to: "...", task: "...", project: "...")` tags from LLM responses.
    static func parseDelegations(from text: String) -> [MochiDelegation] {
        var results: [MochiDelegation] = []
        // Regex pattern: matches @delegate(to: "...", task: "..." [, project: "..."])
        let pattern = #"@delegate\(\s*to:\s*["']([^"']+)["']\s*,\s*task:\s*["']([^"']+)["'](?:\s*,\s*project:\s*["']([^"']+)["'])?\s*\)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let target = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let task = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            var project: String? = nil
            if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                let p = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty { project = p }
            }
            results.append(MochiDelegation(targetPersonaQuery: target, task: task, projectPath: project))
        }

        return results
    }

    // MARK: - Resolving Target Persona

    /// Resolves a MochiPersona by matching ID, exact name, or partial name.
    static func resolvePersona(query: String, in store: PersonaStore? = nil) -> MochiPersona? {
        let store = store ?? PersonaStore.shared
        let candidates = store.personas + MochiPersona.defaultPresets
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = clean.replacingOccurrences(of: "Mochi ", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)

        // 1. Direct ID match
        if let found = candidates.first(where: { $0.id.lowercased() == clean.lowercased() }) {
            return found
        }
        // 2. Direct name match
        if let found = candidates.first(where: { $0.name.lowercased() == clean.lowercased() }) {
            return found
        }
        // 3. Normalized name without "Mochi " prefix (e.g. "Analyst" matches "Mochi Analyst")
        if let found = candidates.first(where: {
            $0.name.replacingOccurrences(of: "Mochi ", with: "", options: .caseInsensitive).lowercased() == stripped.lowercased()
        }) {
            return found
        }
        // 4. Role substring
        return candidates.first { $0.role.lowercased().contains(clean.lowercased()) }
    }

    // MARK: - Claude Terminal Runner

    /// Runs Claude Code (`/opt/homebrew/bin/claude`) in the specified project directory.
    static func runClaude(
        prompt: String,
        directory: String?,
        onToken: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let binary = "/opt/homebrew/bin/claude"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw LocalChatError.serverError("Claude CLI binary not found at \(binary).")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = ["-p", prompt, "--dangerously-skip-permissions"]

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                env["NO_COLOR"] = "1"
                env["CLAUDE_CONFIG_DIR"] = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude"
                process.environment = env

                if let dir = directory, !dir.isEmpty {
                    let expanded = (dir as NSString).expandingTildeInPath
                    if FileManager.default.fileExists(atPath: expanded) {
                        process.currentDirectoryURL = URL(fileURLWithPath: expanded)
                    }
                }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                final class TextBuffer: @unchecked Sendable {
                    private let lock = NSLock()
                    private var text = ""

                    func append(_ chunk: String) -> String {
                        lock.lock()
                        defer { lock.unlock() }
                        text += chunk
                        return text
                    }

                    func value() -> String {
                        lock.lock()
                        defer { lock.unlock() }
                        return text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                let buffer = TextBuffer()
                let outHandle = outPipe.fileHandleForReading

                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    let current = buffer.append(text)
                    DispatchQueue.main.async {
                        onToken?(current)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    outHandle.readabilityHandler = nil

                    let final = buffer.value()

                    DispatchQueue.main.async {
                        if process.terminationStatus == 0 {
                            continuation.resume(returning: final)
                        } else {
                            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                            let errText = String(data: errData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
                            continuation.resume(throwing: LocalChatError.serverError("Claude exited with status \(process.terminationStatus): \(errText)"))
                        }
                    }
                } catch {
                    outHandle.readabilityHandler = nil
                    DispatchQueue.main.async {
                        continuation.resume(throwing: LocalChatError.serverError("Failed to launch Claude Code: \(error.localizedDescription)"))
                    }
                }
            }
        }
    }

    // MARK: - Cloudflare Tunnel Runner

    /// Runs Cloudflare tunnel (`/opt/homebrew/bin/cloudflared`) to expose a local dev server.
    static func launchCloudflareTunnel(port: Int = 3000) async throws -> String {
        let binary = "/opt/homebrew/bin/cloudflared"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw LocalChatError.serverError("cloudflared binary not found at \(binary).")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = ["tunnel", "--url", "http://localhost:\(port)"]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                final class TunnelGate: @unchecked Sendable {
                    private let lock = NSLock()
                    private var resumed = false

                    func complete(with result: Result<String, Error>, continuation: CheckedContinuation<String, Error>) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume(with: result)
                    }
                }

                let gate = TunnelGate()
                let errHandle = errPipe.fileHandleForReading

                errHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    // cloudflared outputs the trycloudflare URL to stderr!
                    if let match = text.range(of: #"https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) {
                        let url = String(text[match])
                        errHandle.readabilityHandler = nil
                        DispatchQueue.main.async {
                            gate.complete(with: .success(url), continuation: continuation)
                        }
                    }
                }

                do {
                    try process.run()
                    // If not found in 10 seconds, timeout
                    DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                        errHandle.readabilityHandler = nil
                        gate.complete(with: .failure(LocalChatError.serverError("Timed out waiting for Cloudflare tunnel URL.")), continuation: continuation)
                    }
                } catch {
                    errHandle.readabilityHandler = nil
                    gate.complete(with: .failure(LocalChatError.serverError("Failed to launch cloudflared: \(error.localizedDescription)")), continuation: continuation)
                }
            }
        }
    }

    // MARK: - Delegation Execution Pipeline

    /// Executes all delegations parsed from an initial response, chaining tasks between Mochis.
    static func processDelegations(
        in text: String,
        caller: MochiPersona,
        state: AppState,
        depth: Int = 0
    ) async {
        guard depth < 5 else { return } // Safe recursion limit

        let delegations = parseDelegations(from: text)
        guard !delegations.isEmpty else { return }

        for delegation in delegations {
            guard let target = resolvePersona(query: delegation.targetPersonaQuery) else {
                continue
            }

            // Animate target Mochi persona visual attributes in Notch!
            let startMsg = ChatMessage(
                role: .assistant,
                content: "🤝 **\(caller.name)** ➔ Delegating to **\(target.name)**:\n> *\(delegation.task)*"
            )
            state.chatHistory.append(startMsg)
            state.stateOverride = .working

            // Trigger emote
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)

            var resultText = ""

            // 1. If target persona has terminal capability (based on persona MD / prompt / skills):
            if target.hasTerminalSkill {
                do {
                    let dir = delegation.projectPath ?? target.connections.projectPath
                    let dirText = dir.isEmpty ? "" : " (Workspace: `\(dir)`)"
                    let statusPlaceholder = ChatMessage(
                        role: .assistant,
                        content: "💻 **\(target.name)** is executing Claude Code in terminal\(dirText)…"
                    )
                    state.chatHistory.append(statusPlaceholder)

                    let output = try await runClaude(prompt: delegation.task, directory: dir.isEmpty ? nil : dir)
                    resultText = output
                } catch {
                    resultText = "⚠️ Claude execution error: \(error.localizedDescription)"
                }
            } else {
                // 2. Persona LLM chat execution:
                let personaPrompt = ClaudeService.makeSystemPrompt(persona: target)
                let messages: [[String: Any]] = [
                    ["role": "system", "content": personaPrompt],
                    ["role": "user", "content": delegation.task]
                ]
                do {
                    let targetProvider = target.providerOverride ?? state.chatProvider
                    let targetModel = target.modelOverride ?? target.defaultModel
                    if targetProvider == .antigravity {
                        let output = try await AntigravityBridge.streamChat(
                            query: delegation.task,
                            context: nil,
                            model: targetModel,
                            messages: messages
                        ) { _ in }
                        resultText = output
                    } else if targetProvider == .zed {
                        let output = try await ZedBridge.streamChat(
                            query: delegation.task,
                            context: nil as PromptContext?,
                            model: targetModel,
                            messages: messages
                        ) { _ in }
                        resultText = output
                    } else {
                        let baseURL: String
                        let authHeader: String
                        var extraHeaders: [String: String] = [:]
                        switch targetProvider {
                        case .openrouter:
                            baseURL = "https://openrouter.ai/api/v1"
                            let key = KeychainStore.shared.get(targetProvider.keychainKey) ?? ""
                            authHeader = "Bearer \(key)"
                            extraHeaders["HTTP-Referer"] = "https://coucou.app"
                            extraHeaders["X-Title"] = "Coucou"
                        case .deepseek:
                            baseURL = "https://api.deepseek.com/v1"
                            let key = KeychainStore.shared.get(targetProvider.keychainKey) ?? ""
                            authHeader = "Bearer \(key)"
                        case .openai:
                            baseURL = "https://api.openai.com/v1"
                            let key = KeychainStore.shared.get(targetProvider.keychainKey) ?? ""
                            authHeader = "Bearer \(key)"
                        case .google:
                            baseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
                            let key = KeychainStore.shared.get(targetProvider.keychainKey) ?? ""
                            authHeader = "Bearer \(key)"
                        case .ollama:
                            baseURL = LocalChat.normaliseURL(state.ollamaServerURL)
                            authHeader = "Bearer ollama"
                        case .lmstudio:
                            baseURL = LocalChat.normaliseURL(state.lmstudioServerURL)
                            authHeader = "Bearer lmstudio"
                        default:
                            baseURL = "https://openrouter.ai/api/v1"
                            let key = KeychainStore.shared.get("openrouter-api-key") ?? ""
                            authHeader = "Bearer \(key)"
                        }

                        let streamBody: [String: Any] = [
                            "model": targetModel,
                            "messages": messages,
                            "stream": true,
                            "max_tokens": 4096,
                        ]
                        let encodedBody = (try? JSONSerialization.data(withJSONObject: streamBody)) ?? Data()
                        let output = try await LocalChat.streamChat(
                            baseURL: baseURL,
                            encodedBody: encodedBody,
                            model: targetModel,
                            authHeader: authHeader,
                            extraHeaders: extraHeaders
                        ) { _ in }
                        resultText = output
                    }
                } catch {
                    resultText = "⚠️ Persona execution error: \(error.localizedDescription)"
                }
            }

            // 3. If target persona has tunnel capability (based on persona MD / prompt / skills):
            if target.hasTunnelSkill && (delegation.task.lowercased().contains("preview") || delegation.task.lowercased().contains("tunnel") || delegation.task.lowercased().contains("cloudflare")) {
                if let url = try? await launchCloudflareTunnel(port: 3000) {
                    resultText += "\n\n🌐 **Cloudflare Tunnel Live**: [\(url)](\(url))"
                }
            }

            // Append completed target result
            let completedMsg = ChatMessage(
                role: .assistant,
                content: "✅ **\(target.name)** completed task:\n\n\(resultText)"
            )
            state.chatHistory.append(completedMsg)
            state.stateOverride = nil

            // 4. Send Discord status update if caller or target has Discord configured:
            if caller.discord.isEnabled {
                let discordConfig = caller.discord
                Task {
                    _ = try? await DiscordService.sendTestMessage(config: discordConfig, persona: target)
                }
            }

            // 5. Recurse if the target generated further delegations (e.g. Analyst delegated to Frontend & Backend)
            if target.connections.canDelegate {
                await processDelegations(in: resultText, caller: target, state: state, depth: depth + 1)
            }
        }
    }
}
