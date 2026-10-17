import Foundation
import AppKit

@main
enum VSCodiumBridgeTests {
    static var pass = 0
    static var fail = 0

    static func check(_ label: String, _ condition: Bool) {
        if condition {
            print("✓ \(label)")
            pass += 1
        } else {
            print("✗ \(label)")
            fail += 1
        }
    }

    static func main() {
        print("Running VSCodiumBridge tests…\n")

        // 1. Bundle identifiers
        check("Bundle IDs contain com.vscodium", VSCodiumBridge.bundleIdentifiers.contains("com.vscodium"))
        check("Bundle IDs contain com.vscodium.codium", VSCodiumBridge.bundleIdentifiers.contains("com.vscodium.codium"))
        check("Bundle IDs contain com.visualstudio.code.oss", VSCodiumBridge.bundleIdentifiers.contains("com.visualstudio.code.oss"))

        // 2. Settings & Extensions paths
        check("Settings URL points to VSCodium settings.json",
              VSCodiumBridge.settingsURL.path.hasSuffix("Library/Application Support/VSCodium/User/settings.json"))
        check("Extensions URL points to .vscode-oss/extensions",
              VSCodiumBridge.extensionsDirectoryURL.path.hasSuffix(".vscode-oss/extensions"))

        // 3. Host detection
        check("Host detection: com.vscodium",
              VSCodiumBridge.isVSCodiumHost(bundleId: "com.vscodium", termProgram: ""))
        check("Host detection: com.vscodium.codium",
              VSCodiumBridge.isVSCodiumHost(bundleId: "com.vscodium.codium", termProgram: ""))
        check("Host detection: com.visualstudio.code.oss",
              VSCodiumBridge.isVSCodiumHost(bundleId: "com.visualstudio.code.oss", termProgram: ""))
        check("Host detection: TERM_PROGRAM=codium",
              VSCodiumBridge.isVSCodiumHost(bundleId: "", termProgram: "codium"))
        check("Host detection: case insensitivity",
              VSCodiumBridge.isVSCodiumHost(bundleId: "COM.VSCODIUM", termProgram: "CODIUM"))

        // Negative cases
        check("Host detection: VS Code rejected",
              !VSCodiumBridge.isVSCodiumHost(bundleId: "com.microsoft.VSCode", termProgram: "vscode"))
        check("Host detection: Cursor rejected",
              !VSCodiumBridge.isVSCodiumHost(bundleId: "com.todesktop.230313mzl4w4u92", termProgram: "vscode"))
        check("Host detection: Warp rejected",
              !VSCodiumBridge.isVSCodiumHost(bundleId: "dev.warp.Warp-Stable", termProgram: "warpterminal"))
        check("Host detection: Apple Terminal rejected",
              !VSCodiumBridge.isVSCodiumHost(bundleId: "com.apple.Terminal", termProgram: "Apple_Terminal"))

        // 4. Candidate paths
        check("Candidate app paths include /Applications/VSCodium.app",
              VSCodiumBridge.candidateAppPaths.contains("/Applications/VSCodium.app"))
        check("Candidate binary paths include /opt/homebrew/bin/codium",
              VSCodiumBridge.candidateBinaryPaths.contains("/opt/homebrew/bin/codium"))

        print("\n\(pass)/\(pass + fail) tests passed.")
        if fail > 0 {
            exit(1)
        }
    }
}
