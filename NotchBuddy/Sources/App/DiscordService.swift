import Foundation

// MARK: - Discord Integration Service

enum DiscordService {

    private struct WebhookPayload: Codable {
        struct Embed: Codable {
            var title: String?
            var description: String?
            var color: Int?
            struct Field: Codable {
                var name: String
                var value: String
                var inline: Bool?
            }
            var fields: [Field]?
            struct Footer: Codable {
                var text: String
            }
            var footer: Footer?
        }
        var content: String?
        var username: String?
        var avatar_url: String?
        var embeds: [Embed]?
    }

    /// Sends a test message / ping to Discord using Webhook URL or Bot Token + Channel ID.
    static func sendTestMessage(config: DiscordIntegrationConfig, persona: MochiPersona) async throws -> String {
        guard config.isEnabled else {
            throw NSError(
                domain: "DiscordService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Discord integration is disabled for this persona."]
            )
        }

        let webhook = config.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !webhook.isEmpty {
            guard let url = URL(string: webhook), url.scheme == "https" else {
                throw NSError(
                    domain: "DiscordService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Discord webhook URL (must start with https://)."]
                )
            }

            let hexClean = persona.bodyColorHex.replacingOccurrences(of: "#", with: "")
            let colorInt = Int(hexClean, radix: 16) ?? 0x7C5CFF
            let activeMCPs = persona.mcpServers.filter(\.isEnabled).map(\.name)
            let mcpList = activeMCPs.isEmpty ? "None" : activeMCPs.joined(separator: ", ")

            let embedDescription = """
            • **Role**: \(persona.role)
            • **Headwear**: \(persona.outfit.displayName)
            • **Connected MCPs**: \(mcpList)
            • **System Instructions**:
            > \(persona.systemPrompt.prefix(140))...
            """

            let payload = WebhookPayload(
                content: "👋 Hello from **\(persona.name)** via Coucou Notch Buddy!",
                username: config.botName.isEmpty ? persona.name : config.botName,
                embeds: [
                    WebhookPayload.Embed(
                        title: "\(persona.name) is Connected & Active",
                        description: embedDescription,
                        color: colorInt,
                        footer: WebhookPayload.Embed.Footer(text: "Coucou Notch Buddy • Persona Discord Bridge")
                    )
                ]
            )

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(payload)

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse else {
                throw NSError(
                    domain: "DiscordService",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "No HTTP response received from Discord."]
                )
            }
            guard (200...299).contains(httpResp.statusCode) else {
                let errBody = String(data: data, encoding: .utf8) ?? "HTTP \(httpResp.statusCode)"
                throw NSError(
                    domain: "DiscordService",
                    code: httpResp.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Discord error (\(httpResp.statusCode)): \(errBody)"]
                )
            }
            return "Webhook test message posted to Discord successfully! 🎉"
        }

        let token = config.botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = config.channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty && !channel.isEmpty {
            guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages") else {
                throw NSError(
                    domain: "DiscordService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Discord channel endpoint."]
                )
            }

            let bodyDict: [String: Any] = [
                "content": "👋 Hello from **\(persona.name)** (\(persona.role)) connected to Coucou Notch Buddy!"
            ]
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse else {
                throw NSError(
                    domain: "DiscordService",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "No HTTP response received from Discord."]
                )
            }
            guard (200...299).contains(httpResp.statusCode) else {
                let errBody = String(data: data, encoding: .utf8) ?? "HTTP \(httpResp.statusCode)"
                throw NSError(
                    domain: "DiscordService",
                    code: httpResp.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Discord Bot API error (\(httpResp.statusCode)): \(errBody)"]
                )
            }
            return "Bot message delivered to Discord channel successfully! 🎉"
        }

        throw NSError(
            domain: "DiscordService",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: "Please provide a valid Discord Webhook URL or Bot Token + Channel ID."]
        )
    }

    /// Posts a message directly to a Discord channel, automatically chunking if > 1900 chars
    static func postChannelMessage(channelId: String, token: String, text: String) async throws {
        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channelId)/messages") else { return }

        // Chunk text into <= 1900 character slices to respect Discord API limits
        var chunks: [String] = []
        var remaining = text
        while !remaining.isEmpty {
            if remaining.count <= 1900 {
                chunks.append(remaining)
                break
            } else {
                let index = remaining.index(remaining.startIndex, offsetBy: 1900)
                chunks.append(String(remaining[..<index]))
                remaining = String(remaining[index...])
            }
        }

        for chunk in chunks {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let bodyDict: [String: Any] = ["content": chunk]
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}

// MARK: - Discord Bot Listener & Mention Dispatcher

@MainActor
final class DiscordBotListener: ObservableObject {
    static let shared = DiscordBotListener()

    @Published private(set) var isListening: Bool = false
    @Published private(set) var lastStatus: String = "Idle"

    private var pollingTask: Task<Void, Never>?
    private var lastSeenMessageId: String?
    private var currentConfig: DiscordIntegrationConfig?
    private var currentPersona: MochiPersona?
    private var isProcessing: Bool = false

    private init() {}

    func start() {
        let persona = PersonaStore.shared.activePersona
        update(for: persona)

        NotificationCenter.default.addObserver(forName: .personaStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                let current = PersonaStore.shared.activePersona
                self?.update(for: current)
            }
        }
    }

    func update(for persona: MochiPersona) {
        currentPersona = persona
        currentConfig = persona.discord

        guard persona.discord.isEnabled,
              !persona.discord.botToken.isEmpty,
              !persona.discord.channelId.isEmpty else {
            stop()
            return
        }

        startListening()
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isListening = false
        lastStatus = "Stopped"
    }

    private func startListening() {
        guard !isListening else { return }
        isListening = true
        lastStatus = "Listening"

        pollingTask?.cancel()
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { break }
                await self?.pollChannel()
            }
        }
    }

    private func pollChannel() async {
        guard let config = currentConfig,
              let persona = currentPersona,
              !config.botToken.isEmpty,
              !config.channelId.isEmpty,
              !isProcessing else { return }

        let token = config.botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let channelId = config.channelId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channelId)/messages?limit=5") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else { return }

            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            guard !jsonArray.isEmpty else { return }

            let botId = decodeBotId(from: token)

            // On first poll, record latest message ID to avoid replaying previous history
            if lastSeenMessageId == nil {
                if let newest = jsonArray.first, let newestId = newest["id"] as? String {
                    lastSeenMessageId = newestId
                }
                return
            }

            // Find new messages (newer than lastSeenMessageId)
            let newMessages = jsonArray.filter { msg in
                guard let id = msg["id"] as? String else { return false }
                guard let last = lastSeenMessageId else { return false }
                if let numId = UInt64(id), let numLast = UInt64(last) {
                    return numId > numLast
                }
                return id > last
            }.reversed()

            for msg in newMessages {
                guard let msgId = msg["id"] as? String else { continue }
                lastSeenMessageId = msgId

                // Ignore messages sent by any bot to prevent infinite reply loops
                if let author = msg["author"] as? [String: Any],
                   let isBot = author["bot"] as? Bool, isBot {
                    continue
                }

                let content = (msg["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { continue }

                // Check if message is a mention to the bot
                let isMentioned: Bool
                if let botId = botId {
                    isMentioned = content.contains("<@\(botId)>") || content.contains("<@!\(botId)>") || content.lowercased().contains(persona.name.lowercased())
                } else {
                    isMentioned = content.lowercased().contains(persona.name.lowercased()) || content.contains("@")
                }

                if isMentioned {
                    var cleanPrompt = content
                    if let botId = botId {
                        cleanPrompt = cleanPrompt
                            .replacingOccurrences(of: "<@\(botId)>", with: "")
                            .replacingOccurrences(of: "<@!\(botId)>", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if cleanPrompt.lowercased().hasPrefix("@" + persona.name.lowercased()) {
                        cleanPrompt = cleanPrompt.dropFirst(persona.name.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    guard !cleanPrompt.isEmpty else { continue }

                    let authorName = (msg["author"] as? [String: Any])?["username"] as? String ?? "User"
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        Task { @MainActor in
                            await self.processDiscordCommand(prompt: cleanPrompt, author: authorName, channelId: channelId, token: token, persona: persona)
                        }
                    }
                    break
                }
            }
        } catch {
            // Transient network error
        }
    }

    @MainActor
    private func processDiscordCommand(prompt: String, author: String, channelId: String, token: String, persona: MochiPersona) async {
        isProcessing = true
        defer { isProcessing = false }

        let state = AppState.shared
        state.stateOverride = .working

        // 1. Post immediate Discord acknowledgement
        let ackText = "⏳ **\(persona.name)** received task from **@\(author)**:\n> *\(prompt)*\n\nWorking on it with Mochi team…"
        _ = try? await DiscordService.postChannelMessage(channelId: channelId, token: token, text: ackText)

        // 2. Count messages before execution
        let preCount = state.chatHistory.count

        // 3. Dispatch through Coucou's multi-provider chat engine (OpenRouter, DeepSeek, Anthropic, Antigravity, etc.)
        await ClaudeService.shared.chat(query: prompt, context: nil, state: state)

        // 4. Retrieve generated response
        var finalResponse: String
        if state.chatHistory.count > preCount, let last = state.chatHistory.last, last.role == .assistant {
            finalResponse = last.content
        } else if let note = state.noteMessage, !note.isEmpty {
            finalResponse = "⚠️ \(note)"
        } else {
            finalResponse = "Task processed."
        }

        // 4b. Execute device orchestration commands if persona has device access
        if persona.deviceAccess.isEnabled {
            let execs = DeviceOrchestrator.parseExecCommands(from: finalResponse)
            let scripts = DeviceOrchestrator.parseAppleScripts(from: finalResponse)

            // Remove raw @exec(...) and @applescript(...) directives from response
            var cleanedText = finalResponse
            for cmd in execs {
                cleanedText = cleanedText.replacingOccurrences(of: "@exec(command: \"\(cmd)\")", with: "")
                cleanedText = cleanedText.replacingOccurrences(of: "@exec(\"\(cmd)\")", with: "")
            }
            for s in scripts {
                cleanedText = cleanedText.replacingOccurrences(of: "@applescript(script: \"\(s)\")", with: "")
                cleanedText = cleanedText.replacingOccurrences(of: "@applescript(\"\(s)\")", with: "")
            }
            cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

            var executionOutputs: [String] = []
            for cmd in execs {
                let res = await DeviceOrchestrator.executeShell(command: cmd)
                if !res.output.isEmpty {
                    executionOutputs.append(res.output)
                }
            }
            for script in scripts {
                let res = await DeviceOrchestrator.executeAppleScript(script: script)
                if !res.output.isEmpty {
                    executionOutputs.append(res.output)
                }
            }

            if cleanedText.isEmpty {
                let live = DeviceOrchestrator.liveSummary()
                cleanedText = """
                ### 🖥️ Mac Status Report
                
                \(live)
                
                > 💡 *Command executed successfully on Mac.*
                """
            }
            finalResponse = cleanedText
        }

        // 5. Post result back to Discord channel
        let replyHeader = "✅ **\(persona.name)** completed task for **@\(author)**:\n\n"
        let fullReply = replyHeader + finalResponse
        _ = try? await DiscordService.postChannelMessage(channelId: channelId, token: token, text: fullReply)

        state.stateOverride = nil
    }

    private func decodeBotId(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard let first = parts.first else { return nil }
        var base64 = String(first)
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64), let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }
}
