import Foundation

// MARK: - PersonaStore Tests

@MainActor
func runPersonaStoreTests() {
    print("Testing PersonaStore & MochiPersona...")

    // 1. Presets validation
    let presets = MochiPersona.defaultPresets
    assert(!presets.isEmpty, "Default presets should not be empty")
    print("  ✓ presets not empty (count: \(presets.count))")

    guard let qa = presets.first(where: { $0.id == "persona_qa" }) else {
        fatalError("QA persona missing")
    }
    assert(qa.outfit == .roundGlasses, "QA should wear round glasses")
    assert(qa.bodyColorHex.uppercased() == "#10B981", "QA should have emerald body")
    assert(qa.mcpServers.contains(where: { $0.name == "Playwright" }), "QA should have Playwright MCP")
    print("  ✓ QA persona has round glasses, emerald color, and Playwright MCP")

    guard let fe = presets.first(where: { $0.id == "persona_frontend" }) else {
        fatalError("Frontend persona missing")
    }
    assert(fe.outfit == .beanie, "Frontend should wear beanie")
    assert(fe.bodyColorHex.uppercased() == "#06B6D4", "Frontend should have cyan body")
    print("  ✓ Frontend persona has beanie and cyan color")

    guard let be = presets.first(where: { $0.id == "persona_backend" }) else {
        fatalError("Backend persona missing")
    }
    assert(be.outfit == .crown, "Backend should wear crown")
    assert(be.bodyColorHex.uppercased() == "#8B5CF6", "Backend should have royal violet body")
    print("  ✓ Backend persona has crown and violet color")

    // 2. Codable serialization test
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
        let data = try encoder.encode(presets)
        let decoded = try decoder.decode([MochiPersona].self, from: data)
        assert(decoded.count == presets.count, "Decoded count should match")
        assert(decoded.first?.name == presets.first?.name, "First persona name should match")
        print("  ✓ MochiPersona array encodes and decodes JSON losslessly")
    } catch {
        fatalError("Serialization failed: \(error)")
    }

    // 3. Custom Persona CRUD
    let store = PersonaStore.shared
    let customId = "persona_test_\(UUID().uuidString)"
    let custom = MochiPersona(
        id: customId,
        name: "Security Tester",
        role: "Pentester",
        systemPrompt: "Find vulnerabilities.",
        outfit: .witchHat,
        bodyColorHex: "#4338CA",
        eyeShape: .line,
        mcpServers: [
            MCPServerConfig(id: "zap", name: "OWASP ZAP", command: "zap.sh", args: [], env: [:], isEnabled: true)
        ]
    )

    store.addPersona(custom)
    assert(store.personas.contains(where: { $0.id == customId }), "Store should contain custom persona")
    print("  ✓ PersonaStore addPersona works")

    store.selectPersona(id: customId)
    assert(store.activePersonaId == customId, "Active persona should be custom persona")
    assert(store.activePersona.name == "Security Tester", "Active persona should resolve to custom")
    print("  ✓ PersonaStore selectPersona works")

    var modified = custom
    modified.name = "Lead Security Pentester"
    modified.outfit = .sunglasses
    store.updatePersona(modified)
    assert(store.activePersona.name == "Lead Security Pentester", "Active persona name should update")
    assert(store.activePersona.outfit == .sunglasses, "Active persona outfit should update")
    print("  ✓ PersonaStore updatePersona works")

    store.deletePersona(id: customId)
    assert(!store.personas.contains(where: { $0.id == customId }), "Store should no longer contain deleted persona")
    print("  ✓ PersonaStore deletePersona permanently removes persona")

    // 4. Discord and Provider/Model overrides test
    var discordPersona = custom
    discordPersona.discord = DiscordIntegrationConfig(
        isEnabled: true,
        webhookURL: "https://discord.com/api/webhooks/123/abc",
        botName: "MochiBot"
    )
    discordPersona.providerOverride = .google
    discordPersona.modelOverride = "gemini-2.5-flash"

    do {
        let enc = try encoder.encode(discordPersona)
        let dec = try decoder.decode(MochiPersona.self, from: enc)
        assert(dec.discord.isEnabled == true, "Discord should be enabled")
        assert(dec.discord.webhookURL == "https://discord.com/api/webhooks/123/abc", "Webhook URL should match")
        assert(dec.discord.botName == "MochiBot", "Bot name should match")
        assert(dec.providerOverride == .google, "Provider override should match")
        assert(dec.modelOverride == "gemini-2.5-flash", "Model override should match")
        print("  ✓ Discord configuration and provider/model overrides round-trip losslessly")
    } catch {
        fatalError("Discord persona serialization failed: \(error)")
    }

    // 5. Device Access & Orchestration test
    var devicePersona = custom
    devicePersona.deviceAccess.grantAll()
    do {
        let enc = try encoder.encode(devicePersona)
        let dec = try decoder.decode(MochiPersona.self, from: enc)
        assert(dec.deviceAccess.isEnabled == true, "Device access should be enabled")
        assert(dec.deviceAccess.canExecuteShell == true, "Shell execution should be enabled")
        assert(dec.deviceAccess.canReadSystemStats == true, "System stats should be enabled")
        assert(dec.deviceAccess.canControlAppleScript == true, "AppleScript should be enabled")
        assert(dec.deviceAccess.canReadFiles == true, "Files should be enabled")
        assert(dec.deviceAccess.autoExecuteAllowed == true, "Auto execute should be enabled")
        assert(dec.detectedSkills.contains(where: { $0.title == "Device Orchestration" }), "Should contain Device Orchestration skill badge")
        print("  ✓ Device access & orchestration configuration round-trips losslessly")
    } catch {
        fatalError("Device access persona serialization failed: \(error)")
    }

    print("\nAll PersonaStore tests passed successfully! 🎉")
}

@main
struct PersonaTestMain {
    static func main() {
        Task { @MainActor in
            runPersonaStoreTests()
            exit(0)
        }
        dispatchMain()
    }
}
