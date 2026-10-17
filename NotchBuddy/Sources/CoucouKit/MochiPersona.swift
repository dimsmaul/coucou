import Foundation

// MARK: - MCP Server Configuration

struct MCPServerConfig: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        command: String,
        args: [String] = [],
        env: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.isEnabled = isEnabled
    }
}

// MARK: - Discord & App Integration Configuration

struct DiscordIntegrationConfig: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var isEnabled: Bool
    var webhookURL: String
    var botToken: String
    var channelId: String
    var botName: String

    init(
        id: String = UUID().uuidString,
        isEnabled: Bool = false,
        webhookURL: String = "",
        botToken: String = "",
        channelId: String = "",
        botName: String = ""
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.webhookURL = webhookURL
        self.botToken = botToken
        self.channelId = channelId
        self.botName = botName
    }
}

// MARK: - Mochi-to-Mochi Connection & Delegation Configuration

struct MochiConnectionConfig: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var canDelegate: Bool
    var connectedPersonaIds: [String]
    var canRunTerminal: Bool
    var canLaunchTunnel: Bool
    var projectPath: String
    var autoExecuteSubtasks: Bool

    init(
        id: String = UUID().uuidString,
        canDelegate: Bool = true,
        connectedPersonaIds: [String] = [],
        canRunTerminal: Bool = false,
        canLaunchTunnel: Bool = false,
        projectPath: String = "",
        autoExecuteSubtasks: Bool = true
    ) {
        self.id = id
        self.canDelegate = canDelegate
        self.connectedPersonaIds = connectedPersonaIds
        self.canRunTerminal = canRunTerminal
        self.canLaunchTunnel = canLaunchTunnel
        self.projectPath = projectPath
        self.autoExecuteSubtasks = autoExecuteSubtasks
    }
}

// MARK: - Device Access & Orchestration Permissions

struct MochiDeviceAccessConfig: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var isEnabled: Bool
    var canExecuteShell: Bool
    var canReadSystemStats: Bool
    var canControlAppleScript: Bool
    var canReadFiles: Bool
    var autoExecuteAllowed: Bool

    init(
        id: String = UUID().uuidString,
        isEnabled: Bool = false,
        canExecuteShell: Bool = false,
        canReadSystemStats: Bool = false,
        canControlAppleScript: Bool = false,
        canReadFiles: Bool = false,
        autoExecuteAllowed: Bool = true
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.canExecuteShell = canExecuteShell
        self.canReadSystemStats = canReadSystemStats
        self.canControlAppleScript = canControlAppleScript
        self.canReadFiles = canReadFiles
        self.autoExecuteAllowed = autoExecuteAllowed
    }

    /// Grants all permissions for full device orchestration
    mutating func grantAll() {
        isEnabled = true
        canExecuteShell = true
        canReadSystemStats = true
        canControlAppleScript = true
        canReadFiles = true
        autoExecuteAllowed = true
    }

    /// Revokes all device access permissions
    mutating func revokeAll() {
        isEnabled = false
        canExecuteShell = false
        canReadSystemStats = false
        canControlAppleScript = false
        canReadFiles = false
    }
}

// MARK: - Mochi Persona

struct MochiPersona: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var role: String
    var systemPrompt: String

    // Visual Customizations
    var outfit: Outfit
    var bodyColorHex: String
    var eyeShape: EyeShape

    // AI & MCP Config
    var defaultProvider: ChatProvider
    var defaultModel: String
    var mcpServers: [MCPServerConfig]
    var isBuiltIn: Bool

    // App Integrations
    var discord: DiscordIntegrationConfig

    // Inter-Mochi Connections & Delegation
    var connections: MochiConnectionConfig

    // Agent Provider & Model Overrides (Optional)
    var providerOverride: ChatProvider?
    var modelOverride: String?

    // Device Access & Orchestration
    var deviceAccess: MochiDeviceAccessConfig

    init(
        id: String = UUID().uuidString,
        name: String,
        role: String,
        systemPrompt: String,
        outfit: Outfit = .none,
        bodyColorHex: String = "#EDEDEF",
        eyeShape: EyeShape = .pill,
        defaultProvider: ChatProvider = .anthropic,
        defaultModel: String = "claude-sonnet-4-6",
        mcpServers: [MCPServerConfig] = [],
        isBuiltIn: Bool = false,
        discord: DiscordIntegrationConfig = DiscordIntegrationConfig(),
        connections: MochiConnectionConfig = MochiConnectionConfig(),
        providerOverride: ChatProvider? = nil,
        modelOverride: String? = nil,
        deviceAccess: MochiDeviceAccessConfig = MochiDeviceAccessConfig()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.systemPrompt = systemPrompt
        self.outfit = outfit
        self.bodyColorHex = bodyColorHex
        self.eyeShape = eyeShape
        self.defaultProvider = defaultProvider
        self.defaultModel = defaultModel
        self.mcpServers = mcpServers
        self.isBuiltIn = isBuiltIn
        self.discord = discord
        self.connections = connections
        self.providerOverride = providerOverride
        self.modelOverride = modelOverride
        self.deviceAccess = deviceAccess
    }

    enum CodingKeys: String, CodingKey {
        case id, name, role, systemPrompt
        case outfit, bodyColorHex, eyeShape
        case defaultProvider, defaultModel, mcpServers, isBuiltIn
        case discord, connections, providerOverride, modelOverride
        case deviceAccess
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(String.self, forKey: .role)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        outfit = try c.decodeIfPresent(Outfit.self, forKey: .outfit) ?? .none
        bodyColorHex = try c.decodeIfPresent(String.self, forKey: .bodyColorHex) ?? "#EDEDEF"
        eyeShape = try c.decodeIfPresent(EyeShape.self, forKey: .eyeShape) ?? .pill
        defaultProvider = try c.decodeIfPresent(ChatProvider.self, forKey: .defaultProvider) ?? .anthropic
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? "claude-sonnet-4-6"
        mcpServers = try c.decodeIfPresent([MCPServerConfig].self, forKey: .mcpServers) ?? []
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        discord = try c.decodeIfPresent(DiscordIntegrationConfig.self, forKey: .discord) ?? DiscordIntegrationConfig()
        connections = try c.decodeIfPresent(MochiConnectionConfig.self, forKey: .connections) ?? MochiConnectionConfig()
        providerOverride = try c.decodeIfPresent(ChatProvider.self, forKey: .providerOverride)
        modelOverride = try c.decodeIfPresent(String.self, forKey: .modelOverride)
        deviceAccess = try c.decodeIfPresent(MochiDeviceAccessConfig.self, forKey: .deviceAccess) ?? MochiDeviceAccessConfig()
    }

    // MARK: - Dynamic Capabilities from Persona MD / System Prompt / Skills

    /// True if the persona's markdown instructions/skills mention terminal execution, claude code, bash, cli, shell, scripts, docker, or coding tools.
    var hasTerminalSkill: Bool {
        if connections.canRunTerminal { return true }
        let text = (systemPrompt + " " + role).lowercased()
        return text.contains("terminal") || text.contains("claude") || text.contains("bash") || text.contains("cli") || text.contains("shell") || text.contains("command") || text.contains("script")
    }

    /// True if the persona's markdown instructions/skills mention Cloudflare tunnels, cloudflared, or preview URLs.
    var hasTunnelSkill: Bool {
        if connections.canLaunchTunnel { return true }
        let text = (systemPrompt + " " + role).lowercased()
        return text.contains("cloudflare") || text.contains("tunnel") || text.contains("cloudflared")
    }

    /// True if the persona's markdown instructions/skills mention Docker or containers.
    var hasDockerSkill: Bool {
        let text = (systemPrompt + " " + role).lowercased()
        return text.contains("docker") || text.contains("container") || text.contains("compose")
    }

    /// True if the persona's markdown instructions/skills mention Vercel or preview deployments.
    var hasVercelSkill: Bool {
        let text = (systemPrompt + " " + role).lowercased()
        return text.contains("vercel") || text.contains("next.js") || text.contains("nextjs")
    }

    /// Auto-detected skills list for UI presentation without needing manual toggles
    var detectedSkills: [(title: String, icon: String, colorHex: String)] {
        var list: [(title: String, icon: String, colorHex: String)] = []
        if hasTerminalSkill {
            list.append(("Terminal & Claude", "terminal.fill", "#3B82F6"))
        }
        if hasTunnelSkill {
            list.append(("Cloudflare Tunnel", "network", "#F59E0B"))
        }
        if hasDockerSkill {
            list.append(("Docker Access", "shippingbox.fill", "#0EA5E9"))
        }
        if hasVercelSkill {
            list.append(("Vercel Deploy", "triangle.fill", "#10B981"))
        }
        if !mcpServers.filter({ $0.isEnabled }).isEmpty {
            list.append(("MCP Tools", "wrench.and.screwdriver.fill", "#8B5CF6"))
        }
        if deviceAccess.isEnabled {
            list.append(("Device Orchestration", "macbook.and.iphone", "#8B5CF6"))
        }
        return list
    }
}

// MARK: - Built-in Presets

extension MochiPersona {

    static let pm = MochiPersona(
        id: "persona_pm",
        name: "Mochi PM",
        role: "Product Manager & Task Coordinator",
        systemPrompt: """
        You are Mochi PM, the Product & Engineering Lead. You coordinate the team of specialist Mochis.
        When given a project feature, task, or bug report:
        1. Clarify requirements and high-level architecture.
        2. Delegate codebase exploration and deep technical analysis to @Mochi Analyst.
        3. Once the analyst identifies issues, create clear subtasks.
        4. Delegate UI/frontend fixes to @Mochi Frontend, API/database fixes to @Mochi Backend, and preview tunnels/deployments to @Mochi DevOps.
        5. To delegate a task to a teammate Mochi, use the tag:
           @delegate(to: "persona_analyst", task: "detailed instruction", project: "optional_path")
        """,
        outfit: .crown,
        bodyColorHex: "#EC4899", // Fuchsia Pink
        eyeShape: .star,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [],
        isBuiltIn: true,
        connections: MochiConnectionConfig(
            canDelegate: true,
            connectedPersonaIds: ["persona_analyst", "persona_frontend", "persona_backend", "persona_devops", "persona_qa"],
            canRunTerminal: false,
            canLaunchTunnel: false
        )
    )

    static let analyst = MochiPersona(
        id: "persona_analyst",
        name: "Mochi Analyst",
        role: "Codebase Auditor & Issue Architect",
        systemPrompt: """
        You are Mochi Analyst, a Senior Technical Architect and Codebase Inspector.
        Your job is to audit codebases, diagnose bugs, and produce structured, actionable issues.
        When given a task or codebase problem:
        1. Inspect the codebase structure, relevant files, and error patterns (using Claude in terminal if enabled).
        2. Identify the root cause or required architecture changes.
        3. Break down the solution into distinct, actionable issues for Frontend and Backend engineers.
        4. Delegate or hand back the issue list with clear file paths, requirements, and acceptance criteria.
        5. To delegate an issue to a teammate Mochi, use the tag:
           @delegate(to: "persona_frontend", task: "fix frontend issue", project: "optional_path")
        """,
        outfit: .roundGlasses,
        bodyColorHex: "#3B82F6", // Royal Blue
        eyeShape: .pill,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [],
        isBuiltIn: true,
        connections: MochiConnectionConfig(
            canDelegate: true,
            connectedPersonaIds: ["persona_pm", "persona_frontend", "persona_backend"],
            canRunTerminal: true,
            canLaunchTunnel: false
        )
    )

    static let standard = MochiPersona(
        id: "persona_general",
        name: "Mochi",
        role: "Coding Companion",
        systemPrompt: "You are Mochi, a concise, friendly, and helpful AI coding assistant living in the Mac notch. Assist the user with coding, code reviews, debugging, and terminal guidance.",
        outfit: .auto,
        bodyColorHex: "#EDEDEF",
        eyeShape: .pill,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [],
        isBuiltIn: true
    )

    static let qaTester = MochiPersona(
        id: "persona_qa",
        name: "Mochi QA",
        role: "QA Automation & Testing",
        systemPrompt: """
        You are an expert QA Automation and Testing Engineer. Your focus is thorough test coverage, edge cases, robust assertions, test automation with Playwright/Puppeteer/Cypress, security analysis, and reproducible bug reports. When tools are available, proactively execute tests and inspect page states.
        """,
        outfit: .roundGlasses,
        bodyColorHex: "#10B981", // Emerald
        eyeShape: .wide,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [
            MCPServerConfig(
                id: "playwright",
                name: "Playwright",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-playwright"],
                env: [:],
                isEnabled: true
            )
        ],
        isBuiltIn: true
    )

    static let frontend = MochiPersona(
        id: "persona_frontend",
        name: "Mochi Frontend",
        role: "Frontend & UI/UX Craftsman",
        systemPrompt: """
        You are a Senior Frontend Engineer and UI/UX Specialist. You build fluid, responsive, accessible interfaces with React, Vue, Svelte, SwiftUI, HTML/CSS, Tailwind CSS, and focus on state management, micro-interactions, clean design tokens, and 60fps animations.
        """,
        outfit: .beanie,
        bodyColorHex: "#06B6D4", // Cyan
        eyeShape: .happy,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [
            MCPServerConfig(
                id: "puppeteer",
                name: "Puppeteer DevTools",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-puppeteer"],
                env: [:],
                isEnabled: true
            )
        ],
        isBuiltIn: true,
        connections: MochiConnectionConfig(
            canDelegate: true,
            connectedPersonaIds: ["persona_pm", "persona_analyst", "persona_backend", "persona_devops"],
            canRunTerminal: true,
            canLaunchTunnel: true
        )
    )

    static let backend = MochiPersona(
        id: "persona_backend",
        name: "Mochi Backend",
        role: "Backend & Systems Architect",
        systemPrompt: """
        You are a Principal Backend and Systems Architect. You design resilient APIs (REST, GraphQL, gRPC), database schemas (Postgres, Redis), concurrency pipelines, security validations, and distributed systems architecture.
        """,
        outfit: .crown,
        bodyColorHex: "#8B5CF6", // Royal Violet
        eyeShape: .pill,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [
            MCPServerConfig(
                id: "postgres",
                name: "PostgreSQL MCP",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-postgres"],
                env: [:],
                isEnabled: false
            )
        ],
        isBuiltIn: true,
        connections: MochiConnectionConfig(
            canDelegate: true,
            connectedPersonaIds: ["persona_pm", "persona_analyst", "persona_frontend"],
            canRunTerminal: true,
            canLaunchTunnel: false
        )
    )

    static let devops = MochiPersona(
        id: "persona_devops",
        name: "Mochi DevOps",
        role: "DevOps & Cloud SRE",
        systemPrompt: """
        You are a DevOps and Site Reliability Engineer. You specialize in CI/CD pipelines, Docker, Kubernetes, Terraform, cloud infrastructure, monitoring, observability, and resilient deployments.
        """,
        outfit: .sunglasses,
        bodyColorHex: "#F59E0B", // Amber
        eyeShape: .dot,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [],
        isBuiltIn: true,
        connections: MochiConnectionConfig(
            canDelegate: true,
            connectedPersonaIds: ["persona_pm", "persona_frontend", "persona_backend"],
            canRunTerminal: true,
            canLaunchTunnel: true
        )
    )

    static let security = MochiPersona(
        id: "persona_security",
        name: "Mochi Security",
        role: "AppSec & Vulnerability Analyst",
        systemPrompt: """
        You are an Application Security and Penetration Testing Specialist. You audit code for OWASP Top 10 vulnerabilities, injection flaws, authentication bugs, cryptographic issues, and privilege escalations.
        """,
        outfit: .witchHat,
        bodyColorHex: "#4338CA", // Midnight Indigo
        eyeShape: .line,
        defaultProvider: .anthropic,
        defaultModel: "claude-sonnet-4-6",
        mcpServers: [],
        isBuiltIn: true
    )

    static let defaultPresets: [MochiPersona] = [
        .pm,
        .analyst,
        .frontend,
        .backend,
        .devops,
        .qaTester,
        .security,
        .standard
    ]
}
