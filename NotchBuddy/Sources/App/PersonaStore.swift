import Foundation
import SwiftUI
import Combine

// MARK: - Persona Local Database Store

@MainActor
final class PersonaStore: ObservableObject {
    static let shared = PersonaStore()

    /// Permanent local database folder in Application Support (with safe fallback for sandboxed test environments)
    static var storageFolder: URL {
        if let customPath = ProcessInfo.processInfo.environment["COUCOU_PERSONAS_DIR"] {
            let customURL = URL(fileURLWithPath: customPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: customURL, withIntermediateDirectories: true)
            return customURL
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let target = appSupport.appendingPathComponent("NotchBuddy/Personas", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            return target
        } catch {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CoucouPersonas", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }

    private static var personasFileURL: URL {
        storageFolder.appendingPathComponent("personas.json")
    }

    private static var activePersonaFileURL: URL {
        storageFolder.appendingPathComponent("active_persona.json")
    }

    @Published private(set) var personas: [MochiPersona] = []
    @Published private(set) var activePersonaId: String = MochiPersona.standard.id
    @Published private(set) var activePersona: MochiPersona = MochiPersona.standard
    @Published private(set) var activeBodyColor: CGColor? = nil
    @Published private(set) var activeEyeShape: EyeShape? = nil

    private func updateCachedActivePersona() {
        let p = personas.first(where: { $0.id == activePersonaId }) ?? personas.first ?? MochiPersona.standard
        activePersona = p
        if p.id == MochiPersona.standard.id && p.bodyColorHex.caseInsensitiveCompare("#EDEDEF") == .orderedSame {
            activeBodyColor = nil
            activeEyeShape = nil
        } else {
            activeBodyColor = cgColorFromHex(p.bodyColorHex)
            activeEyeShape = p.eyeShape
        }
    }

    private init() {
        load()
    }

    // MARK: - Permanent Disk Database Persistence

    func load() {
        let fileURL = Self.personasFileURL
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([MochiPersona].self, from: data),
           !saved.isEmpty {
            self.personas = saved
        } else {
            // Check legacy UserDefaults for one-time migration to permanent local database
            let legacyKey = "mochi_custom_personas_v1"
            if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
               let legacySaved = try? JSONDecoder().decode([MochiPersona].self, from: legacyData),
               !legacySaved.isEmpty {
                self.personas = legacySaved
                UserDefaults.standard.removeObject(forKey: legacyKey)
            } else {
                self.personas = MochiPersona.defaultPresets
            }
            savePersonasToDisk()
        }

        let activeURL = Self.activePersonaFileURL
        if FileManager.default.fileExists(atPath: activeURL.path),
           let activeData = try? Data(contentsOf: activeURL),
           let activeId = String(data: activeData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           personas.contains(where: { $0.id == activeId }) {
            self.activePersonaId = activeId
        } else {
            let legacyActiveKey = "mochi_active_persona_id_v1"
            if let legacyActiveId = UserDefaults.standard.string(forKey: legacyActiveKey),
               personas.contains(where: { $0.id == legacyActiveId }) {
                self.activePersonaId = legacyActiveId
                UserDefaults.standard.removeObject(forKey: legacyActiveKey)
            } else {
                self.activePersonaId = personas.first?.id ?? MochiPersona.standard.id
            }
            saveActivePersonaToDisk()
        }

        updateCachedActivePersona()

        // Warm up MCP client for active persona and notify listeners
        let persona = activePersona
        Task {
            await MCPClientManager.shared.updateServers(for: persona)
            NotificationCenter.default.post(name: .personaStoreDidChange, object: persona)
        }
    }

    private func savePersonasToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(personas) else { return }
        try? data.write(to: Self.personasFileURL, options: .atomic)
    }

    private func saveActivePersonaToDisk() {
        guard let data = activePersonaId.data(using: .utf8) else { return }
        try? data.write(to: Self.activePersonaFileURL, options: .atomic)
    }

    func save() {
        savePersonasToDisk()
        saveActivePersonaToDisk()
    }

    // MARK: - Actions

    func selectPersona(id: String) {
        guard personas.contains(where: { $0.id == id }) else { return }
        activePersonaId = id
        updateCachedActivePersona()
        saveActivePersonaToDisk()

        let persona = activePersona
        Task {
            await MCPClientManager.shared.updateServers(for: persona)
            NotificationCenter.default.post(name: .personaStoreDidChange, object: persona)
        }
        AppState.shared.objectWillChange.send()
    }

    func addPersona(_ persona: MochiPersona) {
        personas.append(persona)
        updateCachedActivePersona()
        save()
        NotificationCenter.default.post(name: .personaStoreDidChange, object: activePersona)
    }

    func updatePersona(_ updated: MochiPersona) {
        if let index = personas.firstIndex(where: { $0.id == updated.id }) {
            let old = personas[index]
            personas[index] = updated
            updateCachedActivePersona()
            save()
            if activePersonaId == updated.id {
                let persona = activePersona
                Task {
                    if old.mcpServers != updated.mcpServers {
                        await MCPClientManager.shared.updateServers(for: persona)
                    }
                    NotificationCenter.default.post(name: .personaStoreDidChange, object: persona)
                }
                AppState.shared.objectWillChange.send()
            }
        }
    }

    func deletePersona(id: String) {
        guard let index = personas.firstIndex(where: { $0.id == id }) else { return }
        personas.remove(at: index)

        if activePersonaId == id {
            activePersonaId = personas.first?.id ?? MochiPersona.standard.id
        }
        updateCachedActivePersona()
        save()
        let active = activePersona
        Task {
            await MCPClientManager.shared.updateServers(for: active)
        }
        AppState.shared.objectWillChange.send()
        NotificationCenter.default.post(name: .personaStoreDidChange, object: active)
    }
}

extension Notification.Name {
    static let personaStoreDidChange = Notification.Name("personaStoreDidChange")
}

