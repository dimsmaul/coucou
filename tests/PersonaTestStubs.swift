import Foundation
import Combine

enum ChatRole: String, Codable {
    case user, assistant, system
}

struct ChatMessage: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var role: ChatRole
    var content: String
}

extension Notification.Name {
    static let triggerEmote = Notification.Name("triggerEmote")
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    var chatHistory: [ChatMessage] = []
    var stateOverride: BotState? = nil
    var chatProvider: ChatProvider = .anthropic
    var noteMessage: String? = nil
    var ollamaServerURL: String = "http://localhost:11434"
    var lmstudioServerURL: String = "http://localhost:1234"
    var editorSummary: EditorInspectionSummary = EditorInspectionSummary(openWindows: [], standaloneAgents: [], totalAgentsCount: 0, formattedReport: "")
}

@MainActor
final class ClaudeService {
    static let shared = ClaudeService()

    static func makeSystemPrompt(persona: MochiPersona? = nil) -> String {
        return persona?.systemPrompt ?? "System prompt"
    }

    func chat(query: String, context: PromptContext?, state: AppState) async {
        state.chatHistory.append(ChatMessage(role: .assistant, content: "Mock reply: " + query))
    }
}
