import Foundation
import AppKit

// MARK: - Editor & Multi-Agent Inspector

public struct RunningAgent: Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public var type: String // "Claude Code", "Codex", "Cline", "Roo Code", "Aider", "Gemini", "Copilot"
    public let cwd: String
    public var cpuPercent: Double
    public var ramMB: Double
    public var command: String

    public init(
        pid: Int32,
        type: String,
        cwd: String,
        cpuPercent: Double = 0.0,
        ramMB: Double = 0.0,
        command: String = ""
    ) {
        self.pid = pid
        self.type = type
        self.cwd = cwd
        self.cpuPercent = cpuPercent
        self.ramMB = ramMB
        self.command = command
    }
}

public struct OpenEditorWindow: Sendable, Identifiable {
    public var id: String { "\(editor):\(title)" }
    public let editor: String // "VSCodium", "Zed", "Code"
    public let title: String
    public let workspaceName: String
    public var workspacePath: String?
    public var agents: [RunningAgent]

    public init(
        editor: String,
        title: String,
        workspaceName: String,
        workspacePath: String? = nil,
        agents: [RunningAgent] = []
    ) {
        self.editor = editor
        self.title = title
        self.workspaceName = workspaceName
        self.workspacePath = workspacePath
        self.agents = agents
    }
}

public struct EditorInspectionSummary: Sendable {
    public let openWindows: [OpenEditorWindow]
    public let standaloneAgents: [RunningAgent]
    public let totalAgentsCount: Int
    public let formattedReport: String

    public init(
        openWindows: [OpenEditorWindow],
        standaloneAgents: [RunningAgent],
        totalAgentsCount: Int,
        formattedReport: String
    ) {
        self.openWindows = openWindows
        self.standaloneAgents = standaloneAgents
        self.totalAgentsCount = totalAgentsCount
        self.formattedReport = formattedReport
    }
}

public enum EditorInspector {

    // MARK: - Telemetry Cache (2.0s TTL)
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedSummary: EditorInspectionSummary?
    nonisolated(unsafe) private static var lastInspectionTime: TimeInterval = 0
    private static let cacheTTL: TimeInterval = 2.0

    /// Inspects open VSCodium, Zed, and VS Code windows, along with all AI agents running inside them.
    public static func inspectEditorsAndAgents() -> EditorInspectionSummary {
        cacheLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = cachedSummary, (now - lastInspectionTime) < cacheTTL {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let fresh = performInspection()

        cacheLock.lock()
        cachedSummary = fresh
        lastInspectionTime = now
        cacheLock.unlock()

        return fresh
    }

    private static func performInspection() -> EditorInspectionSummary {
        // 1. Detect open editor windows via Quartz Window Server
        var windows: [OpenEditorWindow] = []
        let options = CGWindowListOption([.optionAll])
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for win in list {
                let owner = win[kCGWindowOwnerName as String] as? String ?? ""
                let title = win[kCGWindowName as String] as? String ?? ""
                let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let width = bounds["Width"] as? Double ?? 0
                let height = bounds["Height"] as? Double ?? 0
                guard width > 200 && height > 200 else { continue }

                if ["VSCodium", "Code", "Zed"].contains(owner) && !title.isEmpty {
                    var wsName = title
                    if title.contains(" — ") {
                        let parts = title.components(separatedBy: " — ")
                        if owner == "Zed" {
                            wsName = parts.count > 1 ? parts[parts.count - 2] : parts[0]
                        } else {
                            wsName = parts.last?.trimmingCharacters(in: .whitespaces) ?? title
                        }
                    }
                    windows.append(OpenEditorWindow(editor: owner, title: title, workspaceName: wsName))
                }
            }
        }

        // 2. Query running agent processes using lsof for current working directories
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", "lsof -a -c claude -c codex -c cline -c roo -c aider -c gemini -c copilot -d cwd -Fn 2>/dev/null || true"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        var agents: [RunningAgent] = []
        var currentPID: Int32 = 0
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("p"), let p = Int32(line.dropFirst()) {
                currentPID = p
            } else if line.hasPrefix("n") {
                let path = String(line.dropFirst())
                if path != "/" && !path.isEmpty {
                    agents.append(RunningAgent(pid: currentPID, type: "Claude Code", cwd: path))
                }
            }
        }

        // 3. Enrich agent metadata with ps (CPU, RSS RAM, process args to accurately classify agent type)
        if !agents.isEmpty {
            let pidsStr = agents.map { String($0.pid) }.joined(separator: ",")
            let psPipe = Pipe()
            let psProc = Process()
            psProc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            psProc.arguments = ["-c", "ps -p \(pidsStr) -o pid,%cpu,rss,args 2>/dev/null || true"]
            psProc.standardOutput = psPipe
            try? psProc.run()
            psProc.waitUntilExit()

            let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
            let psText = String(data: psData, encoding: .utf8) ?? ""

            var psMap: [Int32: (type: String, cpu: Double, ramMB: Double, cmd: String)] = [:]
            for row in psText.components(separatedBy: "\n").dropFirst() {
                let cols = row.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard cols.count >= 4, let p = Int32(cols[0]) else { continue }
                let cpu = Double(cols[1]) ?? 0.0
                let rssKB = Double(cols[2]) ?? 0.0
                let fullCmd = cols.dropFirst(3).joined(separator: " ")
                let lowerArgs = fullCmd.lowercased()

                var type = "Claude Code"
                if lowerArgs.contains("codex") {
                    type = "Codex"
                } else if lowerArgs.contains("cline") {
                    type = "Cline"
                } else if lowerArgs.contains("roo") {
                    type = "Roo Code"
                } else if lowerArgs.contains("aider") {
                    type = "Aider"
                } else if lowerArgs.contains("gemini") {
                    type = "Gemini Code"
                } else if lowerArgs.contains("copilot") {
                    type = "Copilot"
                }

                psMap[p] = (type: type, cpu: cpu, ramMB: rssKB / 1024.0, cmd: fullCmd)
            }

            for i in 0..<agents.count {
                if let info = psMap[agents[i].pid] {
                    agents[i].type = info.type
                    agents[i].cpuPercent = info.cpu
                    agents[i].ramMB = info.ramMB
                    agents[i].command = info.cmd
                }
            }
        }

        // 4. Map agents to open editor windows by workspace name or directory path
        var standalone: [RunningAgent] = []
        for a in agents {
            var matched = false
            for i in 0..<windows.count {
                let ws = windows[i].workspaceName.lowercased()
                if !ws.isEmpty && a.cwd.lowercased().contains(ws) {
                    windows[i].agents.append(a)
                    if windows[i].workspacePath == nil {
                        windows[i].workspacePath = a.cwd
                    }
                    matched = true
                    break
                }
            }
            if !matched {
                standalone.append(a)
            }
        }

        // 5. Generate human-readable Markdown report
        var report = "### 🖥️ Open Code Editors & Workspaces (\(windows.count) Windows Detected)\n\n"
        if windows.isEmpty {
            report += "*No active VSCodium, Zed, or VS Code editor windows detected.*\n"
        } else {
            for w in windows {
                let agentCounts = Dictionary(grouping: w.agents, by: { $0.type }).mapValues { $0.count }
                let summaryParts = agentCounts.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
                let statusBadge = w.agents.isEmpty ? "⚪" : "🟢"

                report += "- **[\(w.editor)] \(w.workspaceName)**: \(statusBadge) "
                if w.agents.isEmpty {
                    report += "Idle (No active agents)\n"
                } else {
                    report += "**\(w.agents.count) Active Agents** (\(summaryParts))\n"
                }
                report += "  - Window Title: `\(w.title)`\n"
                if let path = w.workspacePath {
                    report += "  - Path: `\(path)`\n"
                }
                if !w.agents.isEmpty {
                    for ag in w.agents {
                        report += "    - 🤖 **\(ag.type)** (PID `\(ag.pid)`): RAM `\(String(format: "%.1f", ag.ramMB)) MB`, CPU `\(String(format: "%.1f", ag.cpuPercent))%`\n"
                    }
                }
            }
        }

        if !standalone.isEmpty {
            report += "\n### 🤖 Standalone / Terminal Agents (\(standalone.count) Agents)\n"
            for ag in standalone {
                report += "- 🤖 **\(ag.type)** (PID `\(ag.pid)`): Directory `\(ag.cwd)` (RAM `\(String(format: "%.1f", ag.ramMB)) MB`, CPU `\(String(format: "%.1f", ag.cpuPercent))%`)\n"
            }
        }

        return EditorInspectionSummary(
            openWindows: windows,
            standaloneAgents: standalone,
            totalAgentsCount: agents.count,
            formattedReport: report.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
