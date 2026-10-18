import Foundation
import MachO
import AppKit

// MARK: - Device Orchestrator

public enum DeviceOrchestrator {

    public struct SystemSnapshot: Sendable {
        public let hostName: String
        public let osVersion: String
        public let cpuUserPercent: Double
        public let cpuSystemPercent: Double
        public let cpuIdlePercent: Double
        public let ramUsedGB: Double
        public let ramTotalGB: Double
        public let ramFreeGB: Double
        public let diskFreeGB: Double
        public let diskTotalGB: Double
    }

    // MARK: - Telemetry TTL Caching
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedSnapshot: SystemSnapshot?
    nonisolated(unsafe) private static var lastSnapshotTime: TimeInterval = 0
    private static let snapshotTTL: TimeInterval = 1.0

    /// Fetches live system hardware and OS metrics (cached with 1.0s TTL to eliminate kernel trap overhead)
    public static func currentSnapshot() -> SystemSnapshot {
        cacheLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = cachedSnapshot, (now - lastSnapshotTime) < snapshotTTL {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let fresh = computeSnapshot()

        cacheLock.lock()
        cachedSnapshot = fresh
        lastSnapshotTime = now
        cacheLock.unlock()

        return fresh
    }

    private static func computeSnapshot() -> SystemSnapshot {
        let host = Host.current().localizedName ?? "Mac"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        // 1. Memory Usage via Mach host VM info
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kerrVM = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / 1_073_741_824.0
        var usedGB: Double = 0
        var freeGB: Double = totalGB
        if kerrVM == KERN_SUCCESS {
            let pageSize = Double(getpagesize())
            let active = Double(stats.active_count) * pageSize
            let wired = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            let usedBytes = active + wired + compressed
            usedGB = usedBytes / 1_073_741_824.0
            freeGB = max(0, totalGB - usedGB)
        }

        // 2. CPU Load via Mach host CPU info
        var cpuLoad = host_cpu_load_info()
        var countCPU = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kerrCPU = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(countCPU)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &countCPU)
            }
        }
        var cpuUser: Double = 0
        var cpuSys: Double = 0
        var cpuIdle: Double = 100
        if kerrCPU == KERN_SUCCESS {
            let u = Double(cpuLoad.cpu_ticks.0)
            let s = Double(cpuLoad.cpu_ticks.1)
            let i = Double(cpuLoad.cpu_ticks.2)
            let n = Double(cpuLoad.cpu_ticks.3)
            let total = u + s + i + n
            if total > 0 {
                cpuUser = (u + n) / total * 100.0
                cpuSys = s / total * 100.0
                cpuIdle = i / total * 100.0
            }
        }

        // 3. Disk Space
        let fs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let diskFree = Double((fs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) / 1_073_741_824.0
        let diskTotal = Double((fs?[.systemSize] as? NSNumber)?.int64Value ?? 0) / 1_073_741_824.0

        return SystemSnapshot(
            hostName: host,
            osVersion: os,
            cpuUserPercent: cpuUser,
            cpuSystemPercent: cpuSys,
            cpuIdlePercent: cpuIdle,
            ramUsedGB: usedGB,
            ramTotalGB: totalGB,
            ramFreeGB: freeGB,
            diskFreeGB: diskFree,
            diskTotalGB: diskTotal
        )
    }

    /// Formatted live hardware summary string for injection into persona system prompt
    public static func liveSummary() -> String {
        let s = currentSnapshot()
        let cpuTotalUsed = s.cpuUserPercent + s.cpuSystemPercent
        return """
        • Device: \(s.hostName)
        • OS: macOS \(s.osVersion)
        • CPU Load: \(String(format: "%.1f", cpuTotalUsed))% (\(String(format: "%.1f", s.cpuUserPercent))% user, \(String(format: "%.1f", s.cpuSystemPercent))% sys, \(String(format: "%.1f", s.cpuIdlePercent))% idle)
        • RAM: \(String(format: "%.2f", s.ramUsedGB)) GB used / \(String(format: "%.2f", s.ramTotalGB)) GB total (\(String(format: "%.2f", s.ramFreeGB)) GB free)
        • Disk: \(String(format: "%.1f", s.diskFreeGB)) GB free / \(String(format: "%.1f", s.diskTotalGB)) GB total
        """
    }

    /// Executes shell command in /bin/zsh, returning stdout/stderr and exit code
    public static func executeShell(command: String) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8) ?? ""
                    let truncated = text.count > 4000 ? String(text.prefix(4000)) + "\n...[truncated]" : text
                    continuation.resume(returning: (truncated.trimmingCharacters(in: .whitespacesAndNewlines), process.terminationStatus))
                } catch {
                    continuation.resume(returning: ("Execution failed: \(error.localizedDescription)", -1))
                }
            }
        }
    }

    /// Executes AppleScript for UI and app automation
    public static func executeAppleScript(script: String) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (text.trimmingCharacters(in: .whitespacesAndNewlines), process.terminationStatus))
                } catch {
                    continuation.resume(returning: ("AppleScript error: \(error.localizedDescription)", -1))
                }
            }
        }
    }

    /// Inspects open code editor windows (VSCodium, Zed, VS Code) and all AI agents running inside each workspace.
    public static func inspectWorkspacesAndAgents() -> EditorInspectionSummary {
        EditorInspector.inspectEditorsAndAgents()
    }

    /// Parses `@exec(command: "...")` directives in persona response
    public static func parseExecCommands(from text: String) -> [String] {
        let pattern = #"@exec\((?:command:\s*)?\"([^\"]+)\"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard m.numberOfRanges >= 2 else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }

    /// Parses `@applescript(script: "...")` directives in persona response
    public static func parseAppleScripts(from text: String) -> [String] {
        let pattern = #"@applescript\((?:script:\s*)?\"([^\"]+)\"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard m.numberOfRanges >= 2 else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
    }

    public struct EditorActionDirective: Sendable {
        public let action: String // "open", "openFile"
        public let editor: String // "zed", "codium"
        public let path: String?
        public let line: Int?
        public let column: Int?
    }

    /// Parses `@editor(action: "...", editor: "...", path: "...")` directives in persona response
    public static func parseEditorDirectives(from text: String) -> [EditorActionDirective] {
        let pattern = #"@editor\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))

        var directives: [EditorActionDirective] = []
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let argsStr = ns.substring(with: m.range(at: 1))

            var action = "open"
            var editor = "zed"
            var path: String? = nil
            var line: Int? = nil
            var column: Int? = nil

            let actionRegex = try? NSRegularExpression(pattern: #"action:\s*\"([^\"]+)\""#)
            if let actMatch = actionRegex?.firstMatch(in: argsStr, range: NSRange(location: 0, length: (argsStr as NSString).length)) {
                action = (argsStr as NSString).substring(with: actMatch.range(at: 1))
            }

            let editorRegex = try? NSRegularExpression(pattern: #"editor:\s*\"([^\"]+)\""#)
            if let edMatch = editorRegex?.firstMatch(in: argsStr, range: NSRange(location: 0, length: (argsStr as NSString).length)) {
                editor = (argsStr as NSString).substring(with: edMatch.range(at: 1))
            }

            let pathRegex = try? NSRegularExpression(pattern: #"path:\s*\"([^\"]+)\""#)
            if let pMatch = pathRegex?.firstMatch(in: argsStr, range: NSRange(location: 0, length: (argsStr as NSString).length)) {
                path = (argsStr as NSString).substring(with: pMatch.range(at: 1))
            }

            let lineRegex = try? NSRegularExpression(pattern: #"line:\s*([0-9]+)"#)
            if let lMatch = lineRegex?.firstMatch(in: argsStr, range: NSRange(location: 0, length: (argsStr as NSString).length)) {
                line = Int((argsStr as NSString).substring(with: lMatch.range(at: 1)))
            }

            let colRegex = try? NSRegularExpression(pattern: #"column:\s*([0-9]+)"#)
            if let cMatch = colRegex?.firstMatch(in: argsStr, range: NSRange(location: 0, length: (argsStr as NSString).length)) {
                column = Int((argsStr as NSString).substring(with: cMatch.range(at: 1)))
            }

            directives.append(EditorActionDirective(action: action, editor: editor, path: path, line: line, column: column))
        }
        return directives
    }
}
