import Foundation

@main
enum ZedBridgeTests {
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
        print("ZedBridge.availableModels")
        let models = ZedBridge.availableModels()
        check("models list is not empty", !models.isEmpty)
        check("contains claude-sonnet-4-6 or claude-sonnet-4-5",
              models.contains(where: { $0.id == "claude-sonnet-4-6" || $0.id == "claude-sonnet-4-5" }))
        check("all models have non-empty labels", models.allSatisfy { !$0.label.isEmpty })
        check("all model IDs are distinct", Set(models.map(\.id)).count == models.count)

        print("ZedBridge.isZedDetected")
        let detected = ZedBridge.isZedDetected()
        check("Zed detected on this Mac", detected)
        check("Zed is installed", ZedBridge.isInstalled)
        check("candidateAppPaths not empty", !ZedBridge.candidateAppPaths.isEmpty)
        let recents = ZedBridge.recentWorkspaces()
        check("recentWorkspaces returns array", recents is [String])

        print("EditorInspector.inspectEditorsAndAgents")
        let summary = EditorInspector.inspectEditorsAndAgents()
        check("inspectEditorsAndAgents returns non-nil report", !summary.formattedReport.isEmpty)
        check("totalAgentsCount >= 0", summary.totalAgentsCount >= 0)
        print("  Found \(summary.openWindows.count) open windows, \(summary.totalAgentsCount) running agents")

        print("ChatProvider.zed integration")
        check("zed display name", ChatProvider.zed.displayName == "Zed AI")
        check("zed accent hex", ChatProvider.zed.accentHex == "#F5AC38")
        check("zed default model", ChatProvider.zed.defaultModel == "claude-sonnet-4-6")
        check("zed pillID", ChatProvider.zed.pillID == "ai_zed")
        check("zed isBridged", ChatProvider.zed.isBridged)
        check("init from pillID", ChatProvider(pillID: "ai_zed") == .zed)

        if failures > 0 {
            print("\n\(failures) test(s) failed.")
            exit(1)
        }
        print("\nAll ZedBridge tests passed.")
    }
}
