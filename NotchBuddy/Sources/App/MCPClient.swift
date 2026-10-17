import Foundation

// MARK: - MCP Tool Model

struct MCPTool: Identifiable, Codable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let description: String
    let inputSchema: [String: AnyCodable]

    init(name: String, description: String = "", inputSchema: [String: AnyCodable] = [:]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    /// Converts to Anthropic tool schema format
    func toAnthropicTool() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "description": description
        ]
        if !inputSchema.isEmpty {
            dict["input_schema"] = inputSchema.mapValues { $0.value }
        } else {
            dict["input_schema"] = [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
        }
        return dict
    }

    /// Converts to OpenAI / Gemini function schema format
    func toOpenAIFunction() -> [String: Any] {
        var fn: [String: Any] = [
            "name": name,
            "description": description
        ]
        if !inputSchema.isEmpty {
            fn["parameters"] = inputSchema.mapValues { $0.value }
        } else {
            fn["parameters"] = [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
        }
        return [
            "type": "function",
            "function": fn
        ]
    }
}

// MARK: - AnyCodable helper for arbitrary JSON values

struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// MARK: - MCP Tool Call Result

struct MCPToolResult: Sendable {
    let text: String
    let isError: Bool

    init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

// MARK: - Native Stdio MCP Client

actor MCPProcessClient {
    let config: MCPServerConfig
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var nextRequestId: Int = 1
    private var isInitialized = false
    private var pendingContinuations: [Int: CheckedContinuation<Data, Error>] = [:]
    private var readBuffer = Data()

    init(config: MCPServerConfig) {
        self.config = config
    }

    deinit {
        if let p = process, p.isRunning {
            p.terminate()
        }
    }

    /// Resolves executable binary path (checking homebrew, system, nvm).
    private static func resolveExecutable(_ command: String) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        let candidates = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Check nvm
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            for v in versions.sorted().reversed() {
                let candidate = "\(nvmDir)/\(v)/bin/\(command)"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Starts and connects to the MCP subprocess.
    func start() async throws {
        guard process == nil else { return }

        guard let executable = Self.resolveExecutable(config.command) else {
            throw NSError(
                domain: "MCPProcessClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Command '\(config.command)' not found on this system."]
            )
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = config.args

        var env = ProcessInfo.processInfo.environment
        for (k, v) in config.env {
            env[k] = v
        }
        // Ensure path includes standard binary locations
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(currentPath)"
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { [weak self] in
                await self?.handleIncomingData(data)
            }
        }

        try proc.run()

        // 1. Send initialize
        let initParams: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [:] as [String: Any],
            "clientInfo": [
                "name": "Coucou",
                "version": "0.4.0"
            ]
        ]
        _ = try await sendRequest(method: "initialize", params: initParams)

        // 2. Send notifications/initialized
        sendNotification(method: "notifications/initialized", params: [:])
        isInitialized = true
    }

    /// Terminates the server process safely.
    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        isInitialized = false
        for (_, cont) in pendingContinuations {
            cont.resume(throwing: NSError(domain: "MCPProcessClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server stopped"]))
        }
        pendingContinuations.removeAll()
    }

    /// Fetches all available tools from the MCP server.
    func listTools() async throws -> [MCPTool] {
        if !isInitialized {
            try await start()
        }
        let response = try await sendRequest(method: "tools/list", params: [:])
        guard let result = response["result"] as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }

        var tools: [MCPTool] = []
        for item in toolsArray {
            guard let name = item["name"] as? String else { continue }
            let desc = item["description"] as? String ?? ""
            var schemaDict: [String: AnyCodable] = [:]
            if let schema = item["inputSchema"] as? [String: Any] {
                for (k, v) in schema {
                    schemaDict[k] = AnyCodable(v)
                }
            }
            tools.append(MCPTool(name: name, description: desc, inputSchema: schemaDict))
        }
        return tools
    }

    /// Executes a tool call on the MCP server.
    func callTool(name: String, argumentsData: Data) async throws -> MCPToolResult {
        if !isInitialized {
            try await start()
        }
        let parsedArgs = (try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any]) ?? [:]
        let params: [String: Any] = [
            "name": name,
            "arguments": parsedArgs
        ]
        let response = try await sendRequest(method: "tools/call", params: params)
        if let err = response["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "Unknown MCP tool error"
            return MCPToolResult(text: msg, isError: true)
        }
        guard let result = response["result"] as? [String: Any] else {
            return MCPToolResult(text: "No result returned", isError: false)
        }
        let isError = result["isError"] as? Bool ?? false
        var texts: [String] = []
        if let contents = result["content"] as? [[String: Any]] {
            for item in contents {
                if let t = item["text"] as? String {
                    texts.append(t)
                }
            }
        }
        let textOutput = texts.joined(separator: "\n")
        return MCPToolResult(text: textOutput.isEmpty ? "(success)" : textOutput, isError: isError)
    }

    // MARK: - Internal JSON-RPC helpers

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        let reqId = nextRequestId
        nextRequestId += 1

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqId,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var msgData = data
        msgData.append(contentsOf: [0x0A]) // \n

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[reqId] = continuation
            do {
                try stdinPipe?.fileHandleForWriting.write(contentsOf: msgData)
            } catch {
                pendingContinuations.removeValue(forKey: reqId)
                continuation.resume(throwing: error)
            }
        }
        return (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]) ?? [:]
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            var msgData = data
            msgData.append(contentsOf: [0x0A])
            try? stdinPipe?.fileHandleForWriting.write(contentsOf: msgData)
        }
    }

    private func handleIncomingData(_ data: Data) {
        readBuffer.append(data)
        while let newlineRange = readBuffer.range(of: Data([0x0A])) {
            let lineData = readBuffer.subdata(in: 0..<newlineRange.lowerBound)
            readBuffer.removeSubrange(0..<newlineRange.upperBound)
            guard !lineData.isEmpty else { continue }
            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let id = json["id"] as? Int,
               let continuation = pendingContinuations.removeValue(forKey: id) {
                continuation.resume(returning: lineData)
            }
        }
    }
}

// MARK: - MCP Client Manager

@MainActor
final class MCPClientManager: ObservableObject {
    static let shared = MCPClientManager()

    private var clients: [String: MCPProcessClient] = [:]
    @Published private(set) var activeTools: [MCPTool] = []
    @Published private(set) var serverStatuses: [String: Bool] = [:] // serverId: isConnected

    private init() {}

    /// Connects to all enabled MCP servers for the given persona and discovers tools.
    func updateServers(for persona: MochiPersona) async {
        // Disconnect existing
        for (_, client) in clients {
            await client.stop()
        }
        clients.removeAll()
        activeTools.removeAll()
        serverStatuses.removeAll()

        let enabledServers = persona.mcpServers.filter {
            $0.isEnabled && !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !enabledServers.isEmpty else { return }

        var gatheredTools: [MCPTool] = []
        for server in enabledServers {
            let client = MCPProcessClient(config: server)
            clients[server.id] = client
            do {
                try await client.start()
                let tools = try await client.listTools()
                gatheredTools.append(contentsOf: tools)
                serverStatuses[server.id] = true
            } catch {
                serverStatuses[server.id] = false
            }
        }
        activeTools = gatheredTools
    }

    /// Executes an MCP tool call across active clients.
    func executeTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        let argsData = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        for (_, client) in clients {
            let tools = try await client.listTools()
            if tools.contains(where: { $0.name == name }) {
                return try await client.callTool(name: name, argumentsData: argsData)
            }
        }
        return MCPToolResult(text: "No connected MCP server handles tool '\(name)'.", isError: true)
    }
}
