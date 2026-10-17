import Foundation

@main
enum MochiMeshTests {
    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            failures += 1
        }
    }

    static func main() async {
        print("MochiConnectionConfig defaults & Presets")
        let defaultConfig = MochiConnectionConfig()
        check("default canDelegate is true", defaultConfig.canDelegate == true)
        check("default connectedPersonaIds is empty", defaultConfig.connectedPersonaIds.isEmpty)
        check("default canRunTerminal is false", defaultConfig.canRunTerminal == false)
        check("default canLaunchTunnel is false", defaultConfig.canLaunchTunnel == false)

        let pm = MochiPersona.pm
        check("pm role is Product Manager & Task Coordinator", pm.role == "Product Manager & Task Coordinator")
        check("pm canDelegate is true", pm.connections.canDelegate == true)
        check("pm connected to analyst", pm.connections.connectedPersonaIds.contains("persona_analyst"))
        check("pm connected to frontend", pm.connections.connectedPersonaIds.contains("persona_frontend"))
        check("pm connected to backend", pm.connections.connectedPersonaIds.contains("persona_backend"))

        let analyst = MochiPersona.analyst
        check("analyst role is Codebase Auditor & Issue Architect", analyst.role == "Codebase Auditor & Issue Architect")
        check("analyst canRunTerminal is true", analyst.connections.canRunTerminal == true)
        check("analyst canDelegate is true", analyst.connections.canDelegate == true)

        let frontend = MochiPersona.frontend
        check("frontend canRunTerminal is true", frontend.connections.canRunTerminal == true)
        check("frontend canLaunchTunnel is true", frontend.connections.canLaunchTunnel == true)

        let devops = MochiPersona.devops
        check("devops canLaunchTunnel is true", devops.connections.canLaunchTunnel == true)

        print("MochiMeshOrchestrator.makeMeshPrompt")
        let allPresets = MochiPersona.defaultPresets
        let pmPrompt = MochiMeshOrchestrator.makeMeshPrompt(for: pm, allPersonas: allPresets)
        check("pm prompt includes Mochi Analyst", pmPrompt.contains("Mochi Analyst"))
        check("pm prompt includes Mochi Frontend", pmPrompt.contains("Mochi Frontend"))
        check("pm prompt includes @delegate instruction", pmPrompt.contains("@delegate(to:"))

        var nonDelegator = MochiPersona.standard
        nonDelegator.connections.canDelegate = false
        let emptyPrompt = MochiMeshOrchestrator.makeMeshPrompt(for: nonDelegator, allPersonas: allPresets)
        check("non-delegating persona gets empty mesh prompt", emptyPrompt.isEmpty)

        print("MochiMeshOrchestrator.parseDelegations")
        let singleSample = """
        I will delegate the analysis to our specialist:
        @delegate(to: "persona_analyst", task: "Analyze authentication flow in eularix project", project: "~/Projects/eularix")
        Please wait for the breakdown.
        """
        let parsedSingle = MochiMeshOrchestrator.parseDelegations(from: singleSample)
        check("parsed exactly 1 delegation", parsedSingle.count == 1)
        check("target is persona_analyst", parsedSingle.first?.targetPersonaQuery == "persona_analyst")
        check("task is accurate", parsedSingle.first?.task == "Analyze authentication flow in eularix project")
        check("project path parsed", parsedSingle.first?.projectPath == "~/Projects/eularix")

        let multiSample = """
        Here is the issue breakdown:
        @delegate(to: "persona_frontend", task: "Fix JWT header injection in auth-client.ts")
        @delegate(to: "persona_backend", task: "Fix 401 refresh token endpoint in auth.controller.ts", project: "/src/backend")
        """
        let parsedMulti = MochiMeshOrchestrator.parseDelegations(from: multiSample)
        check("parsed 2 delegations", parsedMulti.count == 2)
        check("first target is frontend", parsedMulti[0].targetPersonaQuery == "persona_frontend")
        check("first project path is nil", parsedMulti[0].projectPath == nil)
        check("second target is backend", parsedMulti[1].targetPersonaQuery == "persona_backend")
        check("second project path parsed", parsedMulti[1].projectPath == "/src/backend")

        print("MochiMeshOrchestrator.resolvePersona")
        let resolvedById = MochiMeshOrchestrator.resolvePersona(query: "persona_analyst")
        check("resolved by id matches analyst", resolvedById?.id == "persona_analyst")

        let resolvedByName = MochiMeshOrchestrator.resolvePersona(query: "Mochi PM")
        check("resolved by name matches pm", resolvedByName?.id == "persona_pm")

        let resolvedByStripped = MochiMeshOrchestrator.resolvePersona(query: "Analyst")
        check("resolved by stripped name matches analyst", resolvedByStripped?.id == "persona_analyst")

        let resolvedByRole = MochiMeshOrchestrator.resolvePersona(query: "Frontend & UI/UX")
        check("resolved by role substring matches frontend", resolvedByRole?.id == "persona_frontend")

        if failures > 0 {
            print("\n\(failures) test(s) failed.")
            exit(1)
        }
        print("\nAll MochiMesh tests passed.")
    }
}
