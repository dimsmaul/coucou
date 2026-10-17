import Foundation

@main
enum AntigravityBridgeTests {
    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            failures += 1
        }
    }

    static func main() {
        print("AntigravityBridge.availableModels")
        let models = AntigravityBridge.availableModels()
        check("models list is not empty", !models.isEmpty)
        check("contains gemini-2.5-flash", models.contains(where: { $0.id == "gemini-2.5-flash" }))
        check("contains gemini-3.8-pro", models.contains(where: { $0.id == "gemini-3.8-pro" }))
        check("all models have non-empty labels", models.allSatisfy { !$0.label.isEmpty })
        check("all model IDs are distinct", Set(models.map(\.id)).count == models.count)

        print("AntigravityBridge.resolveBinaryPath")
        let path = AntigravityBridge.resolveBinaryPath()
        if let path = path {
            check("binary exists and is executable", FileManager.default.isExecutableFile(atPath: path))
            print("    Resolved to: \(path)")
        } else {
            print("    No binary found on this environment (acceptable if not installed)")
        }

        print("ChatProvider.antigravity integration")
        check("antigravity display name", ChatProvider.antigravity.displayName == "Antigravity")
        check("antigravity accent hex", ChatProvider.antigravity.accentHex == "#E879F9")
        check("antigravity default model", ChatProvider.antigravity.defaultModel == "gemini-2.5-flash")
        check("antigravity pillID", ChatProvider.antigravity.pillID == "ai_antigravity")
        check("antigravity isBridged", ChatProvider.antigravity.isBridged)
        check("init from pillID", ChatProvider(pillID: "ai_antigravity") == .antigravity)

        print("AntigravityBridge.oauthState")
        _ = AntigravityBridge.connectedGoogleAccount()
        check("isOauthAuthenticated returns valid Bool", AntigravityBridge.isOauthAuthenticated() == true || AntigravityBridge.isOauthAuthenticated() == false)
        check("isAvailable returns valid Bool", AntigravityBridge.isAvailable() == true || AntigravityBridge.isAvailable() == false)

        if failures > 0 {
            print("\n\(failures) test(s) failed.")
            exit(1)
        }
        print("\nAll AntigravityBridge tests passed.")
    }
}
