import Foundation
import AppKit

// MARK: - VSCodium Bridge Service

enum VSCodiumBridge {

    /// Standard bundle identifiers for VSCodium builds on macOS.
    static let bundleIdentifiers: [String] = [
        "com.vscodium",
        "com.vscodium.codium",
        "com.visualstudio.code.oss"
    ]

    /// Known application paths where VSCodium is typically installed.
    static let candidateAppPaths: [String] = [
        "/Applications/VSCodium.app",
        "/Applications/VSCodium - Insiders.app",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/VSCodium.app",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/VSCodium - Insiders.app"
    ]

    /// Known CLI binary paths where `codium` is typically located.
    static let candidateBinaryPaths: [String] = [
        "/opt/homebrew/bin/codium",
        "/usr/local/bin/codium",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/codium",
        "/Applications/VSCodium.app/Contents/Resources/app/bin/codium",
        "/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium"
    ]

    /// URL to VSCodium's user settings JSON file.
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VSCodium/User/settings.json")
    }

    /// URL to VSCodium's installed extensions directory.
    static var extensionsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vscode-oss/extensions")
    }

    /// Checks if VSCodium is installed on the system (via bundle ID, app bundle path, or CLI).
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

    /// Checks if a VSCodium instance is currently running.
    static var isRunning: Bool {
        let running = NSWorkspace.shared.runningApplications
        return running.contains { app in
            guard let id = app.bundleIdentifier?.lowercased() else { return false }
            return bundleIdentifiers.contains(id) || id.contains("vscodium") || (id.contains("codium") && !id.contains("vscode"))
        }
    }

    /// Resolves the URL for the installed VSCodium app bundle.
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

    /// Resolves the executable path of the `codium` CLI.
    static func resolveExecutablePath() -> String? {
        let fm = FileManager.default
        for path in candidateBinaryPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Determines whether an incoming hook payload's bundleId and termProgram correspond to VSCodium.
    static func isVSCodiumHost(bundleId: String, termProgram: String) -> Bool {
        let b = bundleId.lowercased()
        let t = termProgram.lowercased()
        if bundleIdentifiers.contains(b) { return true }
        if b.contains("vscodium") { return true }
        if b.contains("codium") && !b.contains("vscode") { return true }
        if t == "codium" || t == "vscodium" { return true }
        return false
    }

    /// Opens VSCodium, optionally targeting a specific workspace folder.
    @discardableResult
    static func open(workspacePath: String? = nil) -> Bool {
        let appURL = resolveAppURL()

        // 1. If a workspace/folder path is provided, open it directly in VSCodium
        if let path = workspacePath, !path.isEmpty {
            let folderURL = URL(fileURLWithPath: path)
            if let appURL = appURL {
                NSWorkspace.shared.open(
                    [folderURL],
                    withApplicationAt: appURL,
                    configuration: .init(),
                    completionHandler: nil
                )
                return true
            } else if let cli = resolveExecutablePath() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cli)
                process.arguments = [path]
                try? process.run()
                return true
            }
        }

        // 2. Bring existing running instance to front
        let runningApps = NSWorkspace.shared.runningApplications
        if let running = runningApps.first(where: { app in
            guard let id = app.bundleIdentifier?.lowercased() else { return false }
            return bundleIdentifiers.contains(id) || id.contains("vscodium") || (id.contains("codium") && !id.contains("vscode"))
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
            try? process.run()
            return true
        }

        return false
    }

    /// Opens a specific file in VSCodium, optionally navigating to line and column.
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
            process.arguments = ["--goto", target]
            if (try? process.run()) != nil {
                return true
            }
        }

        // Fallback to opening file path via app bundle
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
}
