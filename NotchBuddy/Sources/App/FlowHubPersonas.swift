#if !APPSTORE
import SwiftUI
import AppKit

// MARK: - Expressive Mochi Animated Preview

struct ExpressiveMochiPreview: View {
    let persona: MochiPersona
    var size: CGFloat = 64

    @StateObject private var engine = BotEngine()

    var body: some View {
        TimelineView(.animation(paused: false)) { timeline in
            Canvas { context, sz in
                _ = timeline.date
                MochiFrameClock.advance(engine)
                engine.drawOutfitBehind(context: context, size: sz)
                engine.draw(context: context, size: sz)
                engine.drawOutfitFront(context: context, size: sz)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            applyPersona(persona, animated: false)
        }
        .onChange(of: persona.id) { _, _ in
            applyPersona(persona, animated: false)
        }
        .onChange(of: persona.outfit) { _, newOutfit in
            engine.setOutfit(newOutfit, animated: true)
        }
        .onChange(of: persona.bodyColorHex) { _, newHex in
            engine.bodyColor = cgColorFromHex(newHex)
        }
        .onChange(of: persona.eyeShape) { _, newEye in
            engine.permanentEye = newEye
            engine.eyeOverride = newEye
        }
        .onTapGesture {
            engine.triggerEmote(.love, silent: true)
            engine.squash()
        }
        .help("Click to poke Mochi!")
    }

    private func applyPersona(_ p: MochiPersona, animated: Bool) {
        engine.isMini = false
        engine.bodyColor = cgColorFromHex(p.bodyColorHex)
        engine.permanentEye = p.eyeShape
        engine.eyeOverride = p.eyeShape
        engine.setOutfit(p.outfit, animated: animated)
    }
}

// MARK: - FlowHub Personas View

struct FlowHubPersonasView: View {
    @ObservedObject private var store = PersonaStore.shared
    @ObservedObject private var mcpManager = MCPClientManager.shared
    @ObservedObject private var state = AppState.shared

    @State private var selectedId: String = PersonaStore.shared.activePersonaId
    @State private var isTestingMCP: Bool = false
    @State private var mcpTestResult: String? = nil

    @State private var isTestingDiscord: Bool = false
    @State private var discordTestResult: String? = nil

    @State private var showPromptPreview: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private var selectedPersona: MochiPersona? {
        store.personas.first(where: { $0.id == selectedId }) ?? store.personas.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Hero Banner
            HubHero(
                page: .personas,
                title: String(localized: "hub.page.personas", defaultValue: "Personas"),
                subtitle: HubPage.notchSubtitle(.personas)
            )
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            HStack(spacing: 0) {
                // Left list of personas
                sidebarList
                    .frame(width: 230)
                    .background(Color.white.opacity(0.02))

                Divider().opacity(0.2)

                // Right Detail Panel
                if let persona = selectedPersona {
                    personaDetailView(persona)
                } else {
                    emptyPlaceholder
                }
            }
        }
        .onAppear {
            if !store.personas.contains(where: { $0.id == selectedId }) {
                selectedId = store.activePersonaId
            }
        }
    }

    // MARK: - Subviews: Sidebar

    private var sidebarList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Personas"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(HubTheme.text)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Prominent New Persona Button
            Button {
                let newP = MochiPersona(
                    name: "New Buddy",
                    role: "Specialist",
                    systemPrompt: "You are a specialized AI assistant. Assist with your domain knowledge.",
                    outfit: .none,
                    bodyColorHex: "#3B82F6",
                    eyeShape: .pill
                )
                store.addPersona(newP)
                selectedId = newP.id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(String(localized: "New Persona"))
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(HubTheme.accent.opacity(0.15))
                .foregroundColor(HubTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.personas) { persona in
                        personaRow(persona)
                    }
                }
                .padding(.horizontal, 8)
            }

        }
    }

    private var emptyPlaceholder: some View {
        VStack {
            Spacer()
            Text(String(localized: "Select or create a persona"))
                .foregroundColor(HubTheme.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Left Row

    private func personaRow(_ persona: MochiPersona) -> some View {
        let isSelected = persona.id == selectedId
        let isActive = persona.id == store.activePersonaId

        return Button {
            selectedId = persona.id
        } label: {
            HStack(spacing: 10) {
                MochiStill(
                    state: .idle,
                    eye: persona.eyeShape,
                    bodyHex: persona.bodyColorHex,
                    showBadge: false,
                    outfit: persona.outfit
                )
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(persona.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isSelected ? Color.white : HubTheme.text)
                        if isActive {
                            Circle()
                                .fill(HubTheme.accent)
                                .frame(width: 5, height: 5)
                        }
                    }
                    Text(persona.role)
                        .font(.system(size: 10))
                        .foregroundColor(HubTheme.secondary)
                        .lineLimit(1)
                }
                Spacer()

                let activeMCPs = persona.mcpServers.filter { $0.isEnabled }
                if !activeMCPs.isEmpty {
                    Text("\(activeMCPs.count) MCP")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#10B981").opacity(0.2))
                        .foregroundColor(Color(hex: "#10B981"))
                        .clipShape(Capsule())
                }

                if persona.connections.canDelegate || !persona.connections.connectedPersonaIds.isEmpty {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#EC4899"))
                }

                if persona.hasTerminalSkill {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }

                if persona.discord.isEnabled {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#5865F2"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle()) // Enables clicking ANYWHERE in the row!
            .background(isSelected ? HubTheme.card : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Detail Container

    private func personaDetailView(_ persona: MochiPersona) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                detailHeaderSection(persona)
                detailIdentitySection(persona)
                detailPromptSection(persona)
                detailProviderSection(persona)
                detailDeviceAccessSection(persona)
                detailConnectionsSection(persona)
                detailMcpSection(persona)
                detailDiscordSection(persona)
            }
            .padding(24)
        }
    }

    // MARK: - Detail Sub-sections

    @ViewBuilder
    private func detailHeaderSection(_ persona: MochiPersona) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ExpressiveMochiPreview(persona: persona, size: 68)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(persona.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(HubTheme.text)
                    if persona.id == store.activePersonaId {
                        Text(String(localized: "Active in Notch"))
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(HubTheme.accent.opacity(0.2))
                            .foregroundColor(HubTheme.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(persona.role)
                    .font(.system(size: 12))
                    .foregroundColor(HubTheme.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if persona.id != store.activePersonaId {
                    Button {
                        store.selectPersona(id: persona.id)
                        SoundEngine.shared.play("pop")
                        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(String(localized: "Set as Active"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(HubTheme.accent)
                        .foregroundColor(HubTheme.onAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    var copy = persona
                    copy.id = UUID().uuidString
                    copy.name = "\(persona.name) (Copy)"
                    copy.isBuiltIn = false
                    store.addPersona(copy)
                    selectedId = copy.id
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .padding(7)
                        .background(HubTheme.field)
                        .foregroundColor(HubTheme.text)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Duplicate persona")

                if store.personas.count > 1 {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .padding(7)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(Color.red.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete persona")
                    .confirmationDialog("Delete Persona", isPresented: $showDeleteConfirmation) {
                        Button("Delete \"\(persona.name)\"", role: .destructive) {
                            let idToDelete = persona.id
                            store.deletePersona(id: idToDelete)
                            if let next = store.personas.first {
                                selectedId = next.id
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to delete this Mochi persona? This cannot be undone.")
                    }
                }
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func detailIdentitySection(_ persona: MochiPersona) -> some View {
        var bindingPersona = persona
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Identity & Visuals"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(HubTheme.text)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Name"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(HubTheme.secondary)
                    TextField("", text: Binding(
                        get: { persona.name },
                        set: { bindingPersona.name = $0; store.updatePersona(bindingPersona) }
                    ))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(HubTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Role / Skill"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(HubTheme.secondary)
                    TextField("", text: Binding(
                        get: { persona.role },
                        set: { bindingPersona.role = $0; store.updatePersona(bindingPersona) }
                    ))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(HubTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Headwear / Outfit Picker
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Headwear / Outfit (Live Preview)"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(HubTheme.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Outfit.allCases, id: \.self) { outfit in
                            Button {
                                bindingPersona.outfit = outfit
                                store.updatePersona(bindingPersona)
                            } label: {
                                Text(outfit.displayName)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(persona.outfit == outfit ? HubTheme.accent.opacity(0.2) : HubTheme.field)
                                    .foregroundColor(persona.outfit == outfit ? HubTheme.accent : HubTheme.text)
                                    .overlay(
                                        Capsule()
                                            .stroke(persona.outfit == outfit ? HubTheme.accent : Color.clear, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Body Color Picker
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Body Color"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(HubTheme.secondary)

                let colorPalette = [
                    "#EDEDEF", "#10B981", "#06B6D4", "#8B5CF6",
                    "#F59E0B", "#4338CA", "#EC4899", "#EF4444"
                ]

                HStack(spacing: 8) {
                    ForEach(colorPalette, id: \.self) { hex in
                        Button {
                            bindingPersona.bodyColorHex = hex
                            store.updatePersona(bindingPersona)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: persona.bodyColorHex.lowercased() == hex.lowercased() ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Hex", text: Binding(
                        get: { persona.bodyColorHex },
                        set: { bindingPersona.bodyColorHex = $0; store.updatePersona(bindingPersona) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 90)
                    .background(HubTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Eye Shape Picker
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Eye Shape"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(HubTheme.secondary)

                let eyeShapes: [(EyeShape, String)] = [
                    (.pill, "Pill"), (.dot, "Dot"), (.wide, "Wide"),
                    (.happy, "Happy"), (.heart, "Heart"), (.star, "Star"), (.line, "Line")
                ]

                HStack(spacing: 6) {
                    ForEach(eyeShapes, id: \.0) { eye, label in
                        Button {
                            bindingPersona.eyeShape = eye
                            store.updatePersona(bindingPersona)
                        } label: {
                            Text(label)
                                .font(.system(size: 11))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(persona.eyeShape == eye ? HubTheme.accent.opacity(0.2) : HubTheme.field)
                                .foregroundColor(persona.eyeShape == eye ? HubTheme.accent : HubTheme.text)
                                .overlay(
                                    Capsule()
                                        .stroke(persona.eyeShape == eye ? HubTheme.accent : Color.clear, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func detailPromptSection(_ persona: MochiPersona) -> some View {
        var bindingPersona = persona
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Specialized Prompt & Skills"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(HubTheme.text)
                    Text(String(localized: "Instructions injected into Mochi's prompt during chat turns."))
                        .font(.system(size: 11))
                        .foregroundColor(HubTheme.secondary)
                }
                Spacer()

                Picker("", selection: $showPromptPreview) {
                    Text("Edit Code").tag(false)
                    Text("MD Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            if showPromptPreview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if persona.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("No prompt instructions written yet. Switch to Edit Code to write markdown.")
                                .font(.system(size: 12))
                                .foregroundColor(HubTheme.secondary)
                        } else {
                            ChatMarkdownView(markdown: persona.systemPrompt)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .background(HubTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                TextEditor(text: Binding(
                    get: { persona.systemPrompt },
                    set: { bindingPersona.systemPrompt = $0; store.updatePersona(bindingPersona) }
                ))
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120)
                .padding(8)
                .background(HubTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func availableModels(for provider: ChatProvider) -> [(id: String, label: String)] {
        if let fetched = state.fetchedProviderModels[provider], !fetched.isEmpty {
            return fetched
        }
        switch provider {
        case .anthropic:
            return [
                ("claude-sonnet-4-6", "Claude Sonnet 4.6"),
                ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
                ("claude-opus-5-5", "Claude Opus 5.5"),
                ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
            ]
        case .google:
            return [
                ("gemini-2.5-flash", "Gemini 2.5 Flash"),
                ("gemini-2.5-pro", "Gemini 2.5 Pro"),
                ("gemini-2.0-flash", "Gemini 2.0 Flash"),
                ("gemini-1.5-pro", "Gemini 1.5 Pro"),
                ("gemini-1.5-flash", "Gemini 1.5 Flash"),
            ]
        case .openai:
            return [
                ("gpt-4o", "GPT-4o"),
                ("gpt-4o-mini", "GPT-4o Mini"),
                ("o1", "o1"),
                ("o3-mini", "o3-mini"),
                ("gpt-4-turbo", "GPT-4 Turbo"),
            ]
        case .deepseek:
            return [
                ("deepseek-chat", "DeepSeek Chat (V3)"),
                ("deepseek-reasoner", "DeepSeek Reasoner (R1)"),
            ]
        case .qwen:
            return [
                ("qwen-max", "Qwen Max"),
                ("qwen-plus", "Qwen Plus"),
                ("qwen-turbo", "Qwen Turbo"),
                ("qwen-coder-plus", "Qwen Coder Plus"),
            ]
        case .moonshot:
            return [
                ("moonshot-v1-8k", "Moonshot V1 8K"),
                ("moonshot-v1-32k", "Moonshot V1 32K"),
                ("moonshot-v1-128k", "Moonshot V1 128K"),
            ]
        case .openrouter:
            return [
                ("openrouter/auto", "Auto (Best for prompt)"),
                ("anthropic/claude-3.7-sonnet", "Claude 3.7 Sonnet"),
                ("deepseek/deepseek-r1", "DeepSeek R1"),
                ("google/gemini-2.5-pro", "Gemini 2.5 Pro"),
                ("openai/gpt-4o", "GPT-4o"),
            ]
        case .antigravity:
            return AntigravityBridge.availableModels()
        case .zed:
            return ZedBridge.availableModels()
        case .ollama:
            return [
                ("llama3.2", "Llama 3.2"),
                ("qwen2.5-coder", "Qwen 2.5 Coder"),
                ("deepseek-r1", "DeepSeek R1"),
                ("mistral", "Mistral"),
            ]
        case .lmstudio:
            return [
                ("local-model", "Loaded LM Studio Model"),
            ]
        }
    }

    @ViewBuilder
    private func detailProviderSection(_ persona: MochiPersona) -> some View {
        var bindingPersona = persona
        let effectiveProvider = persona.providerOverride ?? state.chatProvider
        let models = availableModels(for: effectiveProvider)
        let currentModel = persona.modelOverride
        let isKnownModel = currentModel == nil || models.contains(where: { $0.id == currentModel })
        let isCustom = !isKnownModel

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Agent Provider & Model Override (Optional)"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(HubTheme.text)
                Text(String(localized: "Bind this persona to a dedicated AI provider and specific model ID."))
                    .font(.system(size: 11))
                    .foregroundColor(HubTheme.secondary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "AI Provider"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(HubTheme.secondary)

                    Picker("", selection: Binding(
                        get: { persona.providerOverride },
                        set: { newProvider in
                            bindingPersona.providerOverride = newProvider
                            if let newP = newProvider {
                                state.fetchModelsIfNeeded(for: newP)
                                bindingPersona.defaultProvider = newP
                            }
                            bindingPersona.modelOverride = nil
                            store.updatePersona(bindingPersona)
                        }
                    )) {
                        Text("Global App Default (\(state.chatProvider.displayName))").tag(Optional<ChatProvider>.none)
                        Divider()
                        ForEach(ChatProvider.allCases, id: \.self) { p in
                            Text(p.displayName).tag(Optional(p))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(4)
                    .background(HubTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(String(localized: "AI Model"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(HubTheme.secondary)
                        if state.loadingProviderModels.contains(effectiveProvider) {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }

                    Picker("", selection: Binding(
                        get: {
                            if isCustom {
                                return "__custom__"
                            }
                            return persona.modelOverride ?? ""
                        },
                        set: { selection in
                            if selection == "" {
                                bindingPersona.modelOverride = nil
                                bindingPersona.defaultModel = effectiveProvider.defaultModel
                            } else if selection == "__custom__" {
                                if isKnownModel {
                                    bindingPersona.modelOverride = ""
                                }
                            } else {
                                bindingPersona.modelOverride = selection
                                bindingPersona.defaultModel = selection
                            }
                            store.updatePersona(bindingPersona)
                        }
                    )) {
                        Text("Default (\(effectiveProvider.defaultModel))").tag("")
                        Divider()
                        ForEach(models, id: \.id) { m in
                            Text(m.label).tag(m.id)
                        }
                        Divider()
                        Text(String(localized: "Custom Model ID…")).tag("__custom__")
                    }
                    .pickerStyle(.menu)
                    .padding(4)
                    .background(HubTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Custom Model ID text field (shown if custom model is selected or entered)
            if isCustom || persona.modelOverride == "" {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Custom Model Identifier"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(HubTheme.secondary)

                    HStack {
                        TextField(effectiveProvider.defaultModel, text: Binding(
                            get: { persona.modelOverride ?? "" },
                            set: { val in
                                let clean = val.trimmingCharacters(in: .whitespacesAndNewlines)
                                bindingPersona.modelOverride = clean.isEmpty ? "" : clean
                                if !clean.isEmpty {
                                    bindingPersona.defaultModel = clean
                                }
                                store.updatePersona(bindingPersona)
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))

                        if persona.modelOverride != nil && persona.modelOverride != "" {
                            Button {
                                bindingPersona.modelOverride = nil
                                bindingPersona.defaultModel = effectiveProvider.defaultModel
                                store.updatePersona(bindingPersona)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(HubTheme.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(7)
                    .background(HubTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            state.fetchModelsIfNeeded(for: effectiveProvider)
        }
    }

    // MARK: - Device Access & Orchestration Section

    @ViewBuilder
    private func detailDeviceAccessSection(_ persona: MochiPersona) -> some View {
        var bindingPersona = persona
        let isAccessGranted = persona.deviceAccess.isEnabled

        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Image(systemName: "macbook.and.iphone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isAccessGranted ? Color.green : Color(hex: "#6366F1"))

                        Text(String(localized: "Device Access & Orchestration"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(HubTheme.text)

                        // Status Badge
                        if isAccessGranted {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text(String(localized: "Full Access Active"))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(Color.green)
                            .clipShape(Capsule())
                        } else {
                            Text(String(localized: "Restricted"))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .foregroundColor(HubTheme.secondary)
                                .clipShape(Capsule())
                        }
                    }

                    Text(String(localized: "Enable this agent to orchestrate this Mac — query live CPU & RAM usage, run terminal commands, and automate system apps."))
                        .font(.system(size: 11))
                        .foregroundColor(HubTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Master Toggle
                Toggle("", isOn: Binding(
                    get: { persona.deviceAccess.isEnabled },
                    set: { enabled in
                        bindingPersona.deviceAccess.isEnabled = enabled
                        if enabled {
                            bindingPersona.deviceAccess.grantAll()
                            bindingPersona.connections.canRunTerminal = true
                        } else {
                            bindingPersona.deviceAccess.revokeAll()
                        }
                        store.updatePersona(bindingPersona)
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }

            // Big 1-Click Request All Access / Grant All Access Action Button
            if !isAccessGranted {
                Button {
                    bindingPersona.deviceAccess.grantAll()
                    bindingPersona.connections.canRunTerminal = true
                    store.updatePersona(bindingPersona)
                    SoundEngine.shared.play("pop")
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "Request All Device Permissions (Grant Full Access)"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(hex: "#6366F1").opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            } else {
                // Live Device Hardware Stats Snapshot Card
                let snapshot = DeviceOrchestrator.currentSnapshot()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(HubTheme.secondary)
                        Text(String(localized: "Live Hardware State (\(snapshot.hostName)):"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(HubTheme.secondary)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        // CPU Pill
                        HStack(spacing: 5) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                                .foregroundColor(Color.cyan)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("CPU")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(HubTheme.secondary)
                                Text("\(String(format: "%.1f", snapshot.cpuUserPercent + snapshot.cpuSystemPercent))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(HubTheme.text)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HubTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // RAM Pill
                        HStack(spacing: 5) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 10))
                                .foregroundColor(Color.purple)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("RAM Used")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(HubTheme.secondary)
                                Text("\(String(format: "%.1f", snapshot.ramUsedGB)) / \(String(format: "%.0f", snapshot.ramTotalGB)) GB")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(HubTheme.text)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HubTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // Disk Pill
                        HStack(spacing: 5) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 10))
                                .foregroundColor(Color.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Disk Free")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(HubTheme.secondary)
                                Text("\(String(format: "%.1f", snapshot.diskFreeGB)) GB")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(HubTheme.text)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HubTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Granular Permission Toggles
                VStack(spacing: 8) {
                    devicePermissionRow(
                        title: "Shell & Terminal Execution (/bin/zsh)",
                        subtitle: "Allows running commands (@exec) directly in user terminal shell",
                        icon: "terminal.fill",
                        iconColor: "#3B82F6",
                        isOn: Binding(
                            get: { persona.deviceAccess.canExecuteShell },
                            set: { v in
                                bindingPersona.deviceAccess.canExecuteShell = v
                                store.updatePersona(bindingPersona)
                            }
                        )
                    )

                    devicePermissionRow(
                        title: "Live Hardware & System Metrics",
                        subtitle: "Provides live CPU, RAM, disk, battery, and process diagnostics to LLM",
                        icon: "gauge.with.needle.fill",
                        iconColor: "#10B981",
                        isOn: Binding(
                            get: { persona.deviceAccess.canReadSystemStats },
                            set: { v in
                                bindingPersona.deviceAccess.canReadSystemStats = v
                                store.updatePersona(bindingPersona)
                            }
                        )
                    )

                    devicePermissionRow(
                        title: "AppleScript & Mac Automation",
                        subtitle: "Allows controlling apps, system settings, volume, and window management",
                        icon: "applescript.fill",
                        iconColor: "#EC4899",
                        isOn: Binding(
                            get: { persona.deviceAccess.canControlAppleScript },
                            set: { v in
                                bindingPersona.deviceAccess.canControlAppleScript = v
                                store.updatePersona(bindingPersona)
                            }
                        )
                    )

                    devicePermissionRow(
                        title: "Workspace & File System Access",
                        subtitle: "Permits reading, inspecting, and editing project files on this device",
                        icon: "folder.fill",
                        iconColor: "#F59E0B",
                        isOn: Binding(
                            get: { persona.deviceAccess.canReadFiles },
                            set: { v in
                                bindingPersona.deviceAccess.canReadFiles = v
                                store.updatePersona(bindingPersona)
                            }
                        )
                    )

                    devicePermissionRow(
                        title: "Auto-Execute Orchestration Tasks",
                        subtitle: "Automatically execute safe inspection commands without blocking prompt",
                        icon: "bolt.fill",
                        iconColor: "#8B5CF6",
                        isOn: Binding(
                            get: { persona.deviceAccess.autoExecuteAllowed },
                            set: { v in
                                bindingPersona.deviceAccess.autoExecuteAllowed = v
                                store.updatePersona(bindingPersona)
                            }
                        )
                    )
                }

                // Revoke Button
                HStack {
                    Spacer()
                    Button {
                        bindingPersona.deviceAccess.revokeAll()
                        store.updatePersona(bindingPersona)
                    } label: {
                        Text(String(localized: "Revoke All Device Access"))
                            .font(.system(size: 11))
                            .foregroundColor(Color.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func devicePermissionRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: iconColor))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(HubTheme.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(HubTheme.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(HubTheme.field)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func detailConnectionsSection(_ persona: MochiPersona) -> some View {
        var bindingPersona = persona
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .foregroundColor(Color(hex: "#EC4899"))
                        Text(String(localized: "Mochi Mesh Team Connections"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(HubTheme.text)
                    }
                    Text(String(localized: "Connect this Mochi with teammate personas to delegate tasks, share findings, and collaborate."))
                        .font(.system(size: 11))
                        .foregroundColor(HubTheme.secondary)
                }
                Spacer()

                Toggle("", isOn: Binding(
                    get: { persona.connections.canDelegate },
                    set: { enabled in
                        bindingPersona.connections.canDelegate = enabled
                        store.updatePersona(bindingPersona)
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }

            if persona.connections.canDelegate {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Connected Teammates:"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(HubTheme.secondary)

                    let otherPersonas = store.personas.filter { $0.id != persona.id }
                    if otherPersonas.isEmpty {
                        Text("No other personas available. Create more personas to connect them.")
                            .font(.system(size: 11))
                            .foregroundColor(HubTheme.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                            ForEach(otherPersonas) { mate in
                                let isConnected = persona.connections.connectedPersonaIds.contains(mate.id)
                                Button {
                                    var current = bindingPersona.connections.connectedPersonaIds
                                    if isConnected {
                                        current.removeAll { $0 == mate.id }
                                    } else {
                                        current.append(mate.id)
                                    }
                                    bindingPersona.connections.connectedPersonaIds = current
                                    store.updatePersona(bindingPersona)
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: mate.bodyColorHex))
                                            .frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(mate.name)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(HubTheme.text)
                                                .lineLimit(1)
                                            Text(mate.role)
                                                .font(.system(size: 9))
                                                .foregroundColor(HubTheme.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 12))
                                            .foregroundColor(isConnected ? HubTheme.accent : HubTheme.secondary.opacity(0.4))
                                    }
                                    .padding(8)
                                    .background(isConnected ? HubTheme.card : Color.white.opacity(0.02))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isConnected ? HubTheme.accent.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider().opacity(0.1).padding(.vertical, 2)

                    // Skills & Tool Capabilities (Derived from Persona MD & Skills)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundColor(HubTheme.accent)
                            Text(String(localized: "Skills & Tool Capabilities (via Persona MD):"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(HubTheme.text)
                        }

                        Text("Capabilities like Terminal execution, Cloudflare tunnel, Docker, Vercel, and MCP are driven directly by your Persona instructions & skills MD.")
                            .font(.system(size: 10))
                            .foregroundColor(HubTheme.secondary)

                        let skills = persona.detectedSkills
                        if !skills.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(skills, id: \.title) { skill in
                                    HStack(spacing: 4) {
                                        Image(systemName: skill.icon)
                                            .font(.system(size: 9))
                                        Text(skill.title)
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: skill.colorHex).opacity(0.12))
                                    .foregroundColor(Color(hex: skill.colorHex))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 2)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Default Project Workspace Path (Optional):")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(HubTheme.secondary)
                            TextField("~/Projects/my-app", text: Binding(
                                get: { persona.connections.projectPath },
                                set: { val in
                                    bindingPersona.connections.projectPath = val
                                    store.updatePersona(bindingPersona)
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(7)
                            .background(HubTheme.field)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func detailMcpSection(_ persona: MochiPersona) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Dedicated MCP Servers"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(HubTheme.text)
                    Text(String(localized: "Dynamic tools via Model Context Protocol (stdio JSON-RPC)."))
                        .font(.system(size: 11))
                        .foregroundColor(HubTheme.secondary)
                }
                Spacer()

                Button {
                    var updated = persona
                    let newServer = MCPServerConfig(
                        name: "Custom Tool",
                        command: "",
                        args: [],
                        env: [:],
                        isEnabled: true
                    )
                    updated.mcpServers.append(newServer)
                    store.updatePersona(updated)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(String(localized: "Add MCP Server"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HubTheme.accent.opacity(0.2))
                    .foregroundColor(HubTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if persona.mcpServers.isEmpty {
                Text(String(localized: "No MCP servers connected to this persona. Click 'Add MCP Server' to configure custom tools."))
                    .font(.system(size: 11))
                    .foregroundColor(HubTheme.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(persona.mcpServers.enumerated()), id: \.element.id) { index, server in
                        mcpServerEditorRow(server: server, persona: persona, index: index)
                    }
                }
            }

            if let result = mcpTestResult {
                HStack(spacing: 6) {
                    Image(systemName: result.contains("Connected") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(result.contains("Connected") ? Color.green : Color.orange)
                    Text(result)
                        .font(.system(size: 11))
                        .foregroundColor(HubTheme.text)
                    Spacer()
                    Button {
                        mcpTestResult = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(HubTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(HubTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func detailDiscordSection(_ persona: MochiPersona) -> some View {
        var bindingPersona = persona
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundColor(Color(hex: "#5865F2"))
                        Text(String(localized: "Discord Integration"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(HubTheme.text)
                    }
                    Text(String(localized: "Connect this persona to Discord to post notifications and updates."))
                        .font(.system(size: 11))
                        .foregroundColor(HubTheme.secondary)
                }
                Spacer()

                Toggle("", isOn: Binding(
                    get: { persona.discord.isEnabled },
                    set: { enabled in
                        bindingPersona.discord.isEnabled = enabled
                        store.updatePersona(bindingPersona)
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }

            if persona.discord.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Discord Webhook URL (Recommended)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(HubTheme.secondary)
                        TextField("https://discord.com/api/webhooks/...", text: Binding(
                            get: { persona.discord.webhookURL },
                            set: { val in
                                bindingPersona.discord.webhookURL = val
                                store.updatePersona(bindingPersona)
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(7)
                        .background(HubTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bot Token (Optional)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(HubTheme.secondary)
                            SecureField("Discord Bot Token", text: Binding(
                                get: { persona.discord.botToken },
                                set: { val in
                                    bindingPersona.discord.botToken = val
                                    store.updatePersona(bindingPersona)
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(7)
                            .background(HubTheme.field)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Channel ID (Optional)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(HubTheme.secondary)
                            TextField("123456789...", text: Binding(
                                get: { persona.discord.channelId },
                                set: { val in
                                    bindingPersona.discord.channelId = val
                                    store.updatePersona(bindingPersona)
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(7)
                            .background(HubTheme.field)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            Task {
                                isTestingDiscord = true
                                discordTestResult = "Connecting to Discord…"
                                do {
                                    let res = try await DiscordService.sendTestMessage(
                                        config: persona.discord,
                                        persona: persona
                                    )
                                    discordTestResult = res
                                } catch {
                                    discordTestResult = "Discord error: \(error.localizedDescription)"
                                }
                                isTestingDiscord = false
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if isTestingDiscord {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 10))
                                }
                                Text(String(localized: "Send Test Message"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#5865F2").opacity(0.3))
                            .foregroundColor(Color(hex: "#7983F5"))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isTestingDiscord || (persona.discord.webhookURL.isEmpty && persona.discord.botToken.isEmpty))
                    }

                    if let res = discordTestResult {
                        HStack(spacing: 6) {
                            Image(systemName: res.contains("successfully") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(res.contains("successfully") ? Color.green : Color.orange)
                            Text(res)
                                .font(.system(size: 11))
                                .foregroundColor(HubTheme.text)
                            Spacer()
                            Button {
                                discordTestResult = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundColor(HubTheme.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(HubTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(16)
        .background(HubTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Dynamic MCP Server Editor Row

    private func mcpServerEditorRow(server: MCPServerConfig, persona: MochiPersona, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(server.isEnabled ? Color(hex: "#10B981") : Color.gray)
                    .frame(width: 8, height: 8)

                TextField("Server Name (e.g. Playwright, Postgres)", text: Binding(
                    get: { server.name },
                    set: { val in
                        var updated = persona
                        updated.mcpServers[index].name = val
                        store.updatePersona(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { server.isEnabled },
                    set: { enabled in
                        var updated = persona
                        updated.mcpServers[index].isEnabled = enabled
                        store.updatePersona(updated)
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.7)

                Button {
                    var updated = persona
                    updated.mcpServers.remove(at: index)
                    store.updatePersona(updated)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(HubTheme.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete MCP Server")
            }

            // Command & Arguments Inputs
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Command / Executable")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(HubTheme.secondary)
                    TextField("e.g. npx, node, uvx, python3", text: Binding(
                        get: { server.command },
                        set: { val in
                            var updated = persona
                            updated.mcpServers[index].command = val
                            store.updatePersona(updated)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(width: 170)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Arguments (space-separated)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(HubTheme.secondary)
                    TextField("e.g. -y @modelcontextprotocol/server-playwright", text: Binding(
                        get: { server.args.joined(separator: " ") },
                        set: { val in
                            var updated = persona
                            updated.mcpServers[index].args = val.split(separator: " ").map(String.init)
                            store.updatePersona(updated)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Environment Variables (Optional)
            VStack(alignment: .leading, spacing: 3) {
                Text("Environment Variables (Optional, KEY=VAL comma-separated)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(HubTheme.secondary)
                TextField("e.g. DATABASE_URL=postgres://..., DEBUG=1", text: Binding(
                    get: { server.env.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") },
                    set: { val in
                        var updated = persona
                        var newEnv: [String: String] = [:]
                        let pairs = val.split(separator: ",")
                        for p in pairs {
                            let parts = p.split(separator: "=", maxSplits: 1)
                            if parts.count == 2 {
                                let k = parts[0].trimmingCharacters(in: .whitespaces)
                                let v = parts[1].trimmingCharacters(in: .whitespaces)
                                if !k.isEmpty { newEnv[k] = v }
                            }
                        }
                        updated.mcpServers[index].env = newEnv
                        store.updatePersona(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Action button: Test Connection
            HStack {
                Spacer()
                Button {
                    Task {
                        isTestingMCP = true
                        let displayName = server.name.isEmpty ? (server.command.isEmpty ? "Server" : server.command) : server.name
                        mcpTestResult = "Connecting to \(displayName)…"
                        let client = MCPProcessClient(config: server)
                        do {
                            try await client.start()
                            let tools = try await client.listTools()
                            mcpTestResult = "Connected to \(displayName)! Discovered \(tools.count) tools: \(tools.map(\.name).joined(separator: ", "))"
                            await client.stop()
                        } catch {
                            mcpTestResult = "Connection failed: \(error.localizedDescription)"
                        }
                        isTestingMCP = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text(String(localized: "Test Connection"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(HubTheme.card)
                    .foregroundColor(HubTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(server.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(HubTheme.field)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
#endif
