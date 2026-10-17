import Foundation
import Combine
import AppKit

// MARK: - Notification name

extension Notification.Name {
    static let gitHubAccountChanged = Notification.Name("coucou.gitHubAccountChanged")
}

// MARK: - GitHubAccount

public struct GitHubAccount: Identifiable, Hashable, Equatable, Sendable {
    public var id: String { "\(host):\(username)" }
    public let host: String
    public let username: String
    public var isActive: Bool
    public var scopes: [String]

    public init(host: String = "github.com", username: String, isActive: Bool = false, scopes: [String] = []) {
        self.host = host
        self.username = username
        self.isActive = isActive
        self.scopes = scopes
    }
}

// MARK: - GitHubAccountManager

@MainActor
public final class GitHubAccountManager: ObservableObject {
    public static let shared = GitHubAccountManager()

    @Published public private(set) var accounts: [GitHubAccount] = []
    @Published public private(set) var activeAccount: GitHubAccount? = nil
    @Published public private(set) var isSwitching: Bool = false
    @Published public var lastError: String? = nil
    @Published public private(set) var lastSwitchedAt: Date? = nil

    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    public static var hostsConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gh/hosts.yml")
    }

    private init() {
        refresh()
        startWatchingConfig()
    }

    deinit {
        fileWatcherSource?.cancel()
    }

    // MARK: - Path Resolution

    public static func resolveGhBinary() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
            "\(fm.homeDirectoryForCurrentUser.path)/.local/bin/gh"
        ]
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Refresh & Parsing

    public func refresh() {
        // 1. Fast offline read from ~/.config/gh/hosts.yml
        let hostsURL = Self.hostsConfigURL
        var parsedAccounts: [GitHubAccount] = []

        if let data = try? Data(contentsOf: hostsURL),
           let content = String(data: data, encoding: .utf8) {
            let (fromYAML, _) = Self.parseHostsYAML(content)
            parsedAccounts = fromYAML
        }

        // 2. Sort accounts: active first, then alphabetical
        parsedAccounts.sort { a, b in
            if a.isActive != b.isActive { return a.isActive && !b.isActive }
            return a.username.localizedCaseInsensitiveCompare(b.username) == .orderedAscending
        }

        let newActive = parsedAccounts.first(where: { $0.isActive })
        let prevActive = self.activeAccount
        self.accounts = parsedAccounts
        self.activeAccount = newActive

        // Automatically sync the active gh account's token with Coucou
        if let active = newActive {
            let userChanged = (prevActive?.username != active.username || prevActive?.host != active.host)
            Task { [weak self] in
                await self?.syncActiveToken(for: active.username, host: active.host, forceReload: userChanged)
            }
        }

        // 3. Background query `gh auth status` for live scopes and validation
        Task { [weak self] in
            guard let statusOutput = await Self.runGhCommand(args: ["auth", "status"]) else { return }
            let detailed = Self.parseAuthStatusOutput(statusOutput)
            guard !detailed.isEmpty else { return }

            await MainActor.run {
                guard let self = self else { return }
                var merged = self.accounts
                for item in detailed {
                    if let idx = merged.firstIndex(where: { $0.username == item.username && $0.host == item.host }) {
                        merged[idx].isActive = item.isActive
                        if !item.scopes.isEmpty { merged[idx].scopes = item.scopes }
                    } else {
                        merged.append(item)
                    }
                }
                merged.sort { a, b in
                    if a.isActive != b.isActive { return a.isActive && !b.isActive }
                    return a.username.localizedCaseInsensitiveCompare(b.username) == .orderedAscending
                }
                let statusActive = merged.first(where: { $0.isActive })
                let statusUserChanged = (self.activeAccount?.username != statusActive?.username || self.activeAccount?.host != statusActive?.host)
                self.accounts = merged
                self.activeAccount = statusActive
                if let active = statusActive, statusUserChanged {
                    Task { [weak self] in
                        await self?.syncActiveToken(for: active.username, host: active.host, forceReload: true)
                    }
                }
            }
        }
    }

    // MARK: - YAML Parser for ~/.config/gh/hosts.yml

    public static func parseHostsYAML(_ content: String) -> (accounts: [GitHubAccount], activeUserByHost: [String: String]) {
        let lines = content.components(separatedBy: .newlines)
        var currentHost: String? = nil
        var activeUserByHost: [String: String] = [:]
        var usersByHost: [String: [String]] = [:]
        var inUsers = false
        var usersIndent = -1

        let reservedKeys: Set<String> = ["oauth_token", "git_protocol", "user", "users"]

        for line in lines {
            // Count leading spaces
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Root level: host declaration (e.g. "github.com:")
            if indent == 0 && trimmed.hasSuffix(":") {
                currentHost = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                inUsers = false
                usersIndent = -1
                continue
            }

            guard let host = currentHost else { continue }

            if trimmed.hasPrefix("user:") {
                let userVal = trimmed.dropFirst("user:".count).trimmingCharacters(in: .whitespaces)
                activeUserByHost[host] = userVal
                continue
            }

            if trimmed == "users:" {
                inUsers = true
                usersIndent = indent
                continue
            }

            if inUsers {
                // If indent dropped back to or below `users:` indent, we left the users map
                if indent <= usersIndent {
                    inUsers = false
                    usersIndent = -1
                    if trimmed.hasPrefix("user:") {
                        let userVal = trimmed.dropFirst("user:".count).trimmingCharacters(in: .whitespaces)
                        activeUserByHost[host] = userVal
                    }
                    continue
                }

                // In GitHub CLI hosts.yml, users are indented once under `users:`
                // e.g. `users:` (indent 4) -> `username:` (indent 8)
                if trimmed.hasSuffix(":") {
                    let key = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                    if !reservedKeys.contains(key) && (usersIndent < 0 || indent <= usersIndent + 4) {
                        if usersByHost[host] == nil { usersByHost[host] = [] }
                        if !usersByHost[host]!.contains(key) {
                            usersByHost[host]!.append(key)
                        }
                    }
                }
            }
        }

        var result: [GitHubAccount] = []
        for (host, users) in usersByHost {
            let active = activeUserByHost[host]
            for u in users {
                result.append(GitHubAccount(host: host, username: u, isActive: (u == active)))
            }
            // If active user is specified but wasn't listed under users:, still include it
            if let active = active, !users.contains(active) {
                result.append(GitHubAccount(host: host, username: active, isActive: true))
            }
        }

        return (result, activeUserByHost)
    }

    // MARK: - `gh auth status` Parser

    public static func parseAuthStatusOutput(_ text: String) -> [GitHubAccount] {
        var accounts: [GitHubAccount] = []
        let lines = text.components(separatedBy: .newlines)
        var currentHost = "github.com"
        var currentUsername: String? = nil
        var currentIsActive = false
        var currentScopes: [String] = []

        func commitCurrent() {
            guard let username = currentUsername else { return }
            accounts.append(GitHubAccount(host: currentHost, username: username, isActive: currentIsActive, scopes: currentScopes))
            currentUsername = nil
            currentIsActive = false
            currentScopes = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Host line without leading spaces e.g. "github.com"
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.contains(".") {
                commitCurrent()
                currentHost = trimmed
                continue
            }

            // Account line: "✓ Logged in to github.com account username (keyring)"
            // or "X Failed to log in to github.com account username (default)"
            if trimmed.contains("account ") {
                commitCurrent()
                let parts = trimmed.components(separatedBy: "account ")
                if parts.count > 1 {
                    let after = parts[1].trimmingCharacters(in: .whitespaces)
                    let user = after.components(separatedBy: " ").first ?? ""
                    if !user.isEmpty {
                        currentUsername = user
                    }
                }
                continue
            }

            if trimmed.hasPrefix("- Active account:") {
                currentIsActive = trimmed.contains("true")
                continue
            }

            if trimmed.hasPrefix("- Token scopes:") {
                let scopeStr = trimmed.dropFirst("- Token scopes:".count).trimmingCharacters(in: .whitespaces)
                let cleaned = scopeStr
                    .replacingOccurrences(of: "'", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                currentScopes = cleaned.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                continue
            }
        }
        commitCurrent()

        return accounts
    }

    // MARK: - Switching Account

    @discardableResult
    public func switchAccount(to username: String, host: String = "github.com") async -> Bool {
        guard !isSwitching else { return false }
        isSwitching = true
        lastError = nil
        defer { isSwitching = false }

        // 1. Run official `gh auth switch` CLI command
        var cliSuccess = false
        if let output = await Self.runGhCommand(args: ["auth", "switch", "--hostname", host, "--user", username]) {
            // Check for success or error in output
            if output.contains("Switched active account") || !output.lowercased().contains("error") {
                cliSuccess = true
            }
        }

        // 2. Direct ~/.config/gh/hosts.yml sync to guarantee the active user is updated
        let hostsUpdated = Self.updateHostsYAML(activeUser: username, host: host)

        if !cliSuccess && !hostsUpdated {
            lastError = "Failed to switch GitHub account to \(username)."
            return false
        }

        // 3. Retrieve token for the newly active user and sync with Coucou's KeychainStore
        await syncActiveToken(for: username, host: host, forceReload: true)

        // 4. Update published accounts
        var updated = accounts
        for i in updated.indices {
            if updated[i].host == host {
                updated[i].isActive = (updated[i].username == username)
            }
        }
        self.accounts = updated
        self.activeAccount = updated.first(where: { $0.host == host && $0.username == username })
        self.lastSwitchedAt = Date()

        // 5. Play confirmation sound and post notification
        SoundEngine.shared.play("blip")
        NotificationCenter.default.post(name: .gitHubAccountChanged, object: username)

        return true
    }

    // MARK: - Token Synchronization

    @discardableResult
    public func syncActiveToken(for username: String, host: String = "github.com", forceReload: Bool = false) async -> Bool {
        guard let token = await fetchToken(for: username, host: host) else {
            return false
        }
        let currentToken = KeychainStore.shared.get("github-token")
        let tokenChanged = (currentToken != token)

        if tokenChanged || forceReload {
            KeychainStore.shared.set("github-token", value: token)
            // Invalidate stale caches from previous persona so pulse, activity and stats refetch
            AppState.shared.githubPulse = nil
            AppState.shared.githubActivity = nil
            AppState.shared.githubStats = nil
            // Immediately trigger poller with the new token
            GithubPoller.shared.triggerPulseNow()
            GithubPoller.shared.refreshActivityIfStale(maxAge: 0)
            GithubPoller.shared.refreshStats()
            NotificationCenter.default.post(name: .gitHubAccountChanged, object: username)
        }
        return true
    }

    public func fetchToken(for username: String, host: String = "github.com") async -> String? {
        guard let output = await Self.runGhCommand(args: ["auth", "token", "--hostname", host, "--user", username]) else {
            return nil
        }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - Direct File Modification Fallback

    public static func updateHostsYAML(activeUser: String, host: String = "github.com") -> Bool {
        let url = hostsConfigURL
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return false
        }

        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var inTargetHost = false
        var userReplaced = false

        for line in lines {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if indent == 0 && trimmed.hasSuffix(":") {
                let h = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                if inTargetHost && !userReplaced {
                    // Append user line before moving to next host
                    newLines.append("    user: \(activeUser)")
                    userReplaced = true
                }
                inTargetHost = (h == host)
                newLines.append(line)
                continue
            }

            if inTargetHost && trimmed.hasPrefix("user:") {
                newLines.append("    user: \(activeUser)")
                userReplaced = true
                continue
            }

            newLines.append(line)
        }

        if inTargetHost && !userReplaced {
            newLines.append("    user: \(activeUser)")
        }

        let newContent = newLines.joined(separator: "\n")
        do {
            try newContent.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Process Execution

    private static func runGhCommand(args: [String]) async -> String? {
        guard let binPath = resolveGhBinary() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binPath)
                process.arguments = args

                // Supply user environment so PATH and Homebrew tools are visible
                var env = ProcessInfo.processInfo.environment
                if let path = env["PATH"] {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + path
                } else {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                }
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let str = String(data: data, encoding: .utf8)
                    continuation.resume(returning: str)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - File Watcher

    private func startWatchingConfig() {
        let path = Self.hostsConfigURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.refresh()
            // If renamed or deleted, re-arm watcher after a short delay
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.stopWatchingConfig()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.startWatchingConfig()
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.fileWatcherSource = source
    }

    private func stopWatchingConfig() {
        if let s = fileWatcherSource {
            s.cancel()
            fileWatcherSource = nil
        }
        fileDescriptor = -1
    }
}
