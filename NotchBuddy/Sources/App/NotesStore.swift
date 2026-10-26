import Foundation

// MARK: - Note Item Model

public struct NoteItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Quick Notes",
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Notion-Style Live Block Models

public enum NoteBlockKind: Equatable, Codable, Sendable {
    case paragraph
    case heading(level: Int)
    case todo(isChecked: Bool)
    case bullet
    case quote
    case code(lang: String)
}

public struct NoteBlock: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: NoteBlockKind
    public var text: String

    public init(id: UUID = UUID(), kind: NoteBlockKind = .paragraph, text: String = "") {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

// MARK: - Markdown Block Model for Notes

public enum NoteMDBlock: Equatable, Identifiable {
    public var id: String {
        switch self {
        case .heading(let level, let text, let idx):
            return "h-\(level)-\(idx)-\(text.prefix(12))"
        case .taskItem(let idx, let isChecked, let text):
            return "task-\(idx)-\(isChecked)-\(text.prefix(12))"
        case .listItem(let prefix, let text, let indent, let idx):
            return "list-\(idx)-\(prefix)-\(indent)-\(text.prefix(12))"
        case .codeBlock(let lang, _, let idx):
            return "code-\(idx)-\(lang)"
        case .quote(let text, let idx):
            return "quote-\(idx)-\(text.prefix(12))"
        case .paragraph(let text, let idx):
            return "para-\(idx)-\(text.prefix(12))"
        case .rule(let idx):
            return "rule-\(idx)"
        }
    }

    case heading(level: Int, text: String, lineIndex: Int)
    case taskItem(lineIndex: Int, isChecked: Bool, text: String)
    case listItem(prefix: String, text: String, indent: Int, lineIndex: Int)
    case codeBlock(lang: String, code: String, lineIndex: Int)
    case quote(text: String, lineIndex: Int)
    case paragraph(text: String, lineIndex: Int)
    case rule(lineIndex: Int)
}

// MARK: - Checkbox Line Info

public struct NoteTaskLine: Equatable {
    public let isChecked: Bool
    public let prefix: String      // e.g. "- " or "* " or ""
    public let text: String        // remaining task label
    public let lineIndex: Int
}

// MARK: - Notes Markdown Engine

public enum NotesMarkdownEngine {

    /// Parses a single line to see if it represents a checkbox task item.
    /// Supports:
    /// - `[] Task` or `[ ] Task` (unchecked)
    /// - `[x] Task` or `[X] Task` (checked)
    /// - `- [] Task`, `- [ ] Task`, `* [ ] Task`, `+ [ ] Task`
    /// - `- [x] Task`, `- [X] Task`, `* [x] Task`, `+ [x] Task`
    public static func parseTaskLine(_ rawLine: String, at index: Int) -> NoteTaskLine? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

        var prefix = ""
        var rest = trimmed

        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            prefix = String(rest.prefix(2))
            rest = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        // Check for checked marker: [x] or [X]
        if rest.hasPrefix("[x]") || rest.hasPrefix("[X]") {
            let text = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return NoteTaskLine(isChecked: true, prefix: prefix, text: text, lineIndex: index)
        }

        // Check for unchecked marker: [ ] or []
        if rest.hasPrefix("[ ]") {
            let text = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return NoteTaskLine(isChecked: false, prefix: prefix, text: text, lineIndex: index)
        }

        if rest.hasPrefix("[]") {
            let text = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return NoteTaskLine(isChecked: false, prefix: prefix, text: text, lineIndex: index)
        }

        return nil
    }

    /// Toggles the checkbox on a line (if present).
    /// If unchecked (`[]` or `[ ]`), replaces with `[x]`.
    /// If checked (`[x]` or `[X]`), replaces with `[ ]`.
    /// Preserves existing indentation and list bullet prefixes (`- `, `* `, etc.).
    public static func toggleCheckboxLine(_ rawLine: String) -> String {
        let leadingSpaces = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

        var prefix = ""
        var rest = trimmed

        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            prefix = String(rest.prefix(2))
            rest = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        if rest.hasPrefix("[x]") || rest.hasPrefix("[X]") {
            let text = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let space = text.isEmpty ? "" : " "
            return "\(leadingSpaces)\(prefix)[ ]\(space)\(text)"
        }

        if rest.hasPrefix("[ ]") {
            let text = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let space = text.isEmpty ? "" : " "
            return "\(leadingSpaces)\(prefix)[x]\(space)\(text)"
        }

        if rest.hasPrefix("[]") {
            let text = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let space = text.isEmpty ? "" : " "
            return "\(leadingSpaces)\(prefix)[x]\(space)\(text)"
        }

        return rawLine
    }

    /// Parses multi-line markdown text into structured blocks for rendering.
    public static func parse(_ input: String) -> [NoteMDBlock] {
        var blocks: [NoteMDBlock] = []
        let lines = input.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // 1. Fenced Code Block
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                let startLine = i
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(lang: lang, code: codeLines.joined(separator: "\n"), lineIndex: startLine))
                if i < lines.count { i += 1 }
                continue
            }

            // 2. ATX Headings: # Heading
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                var level = 0
                var rest = trimmed
                while rest.hasPrefix("#") {
                    level += 1
                    rest = String(rest.dropFirst())
                }
                if rest.hasPrefix(" ") || rest.isEmpty {
                    let text = rest.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        blocks.append(.heading(level: min(level, 6), text: text, lineIndex: i))
                        i += 1
                        continue
                    }
                }
            }

            // 3. Task Items with Checkbox: [] / [ ] / [x]
            if let task = parseTaskLine(line, at: i) {
                blocks.append(.taskItem(lineIndex: i, isChecked: task.isChecked, text: task.text))
                i += 1
                continue
            }

            // 4. Horizontal Rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.rule(lineIndex: i))
                i += 1
                continue
            }

            // 5. Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                let text = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                blocks.append(.quote(text: text, lineIndex: i))
                i += 1
                continue
            }

            // 6. Regular List Item
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let indent = leadingSpaces / 2
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(.listItem(prefix: "•", text: text, indent: indent, lineIndex: i))
                i += 1
                continue
            }

            // 7. Ordered List Item
            if let range = trimmed.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                let numStr = String(trimmed[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
                let number = numStr.components(separatedBy: ".").first ?? "1"
                let text = String(trimmed[range.upperBound...])
                blocks.append(.listItem(prefix: "\(number).", text: text, indent: indent, lineIndex: i))
                i += 1
                continue
            }

            // 8. Blank Line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 9. Standard Paragraph
            blocks.append(.paragraph(text: trimmed, lineIndex: i))
            i += 1
        }

        return blocks
    }

    /// Converts multi-line markdown into Notion-style editable blocks.
    public static func markdownToBlocks(_ markdown: String) -> [NoteBlock] {
        if markdown.isEmpty {
            return [NoteBlock(kind: .paragraph, text: "")]
        }
        var blocks: [NoteBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(NoteBlock(kind: .code(lang: lang), text: codeLines.joined(separator: "\n")))
                if i < lines.count { i += 1 }
                continue
            }

            // Headings
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                var level = 0
                var rest = trimmed
                while rest.hasPrefix("#") {
                    level += 1
                    rest = String(rest.dropFirst())
                }
                if rest.hasPrefix(" ") || rest.isEmpty {
                    let text = rest.trimmingCharacters(in: .whitespaces)
                    blocks.append(NoteBlock(kind: .heading(level: min(level, 3)), text: text))
                    i += 1
                    continue
                }
            }

            // Checkbox / Task items
            if let task = parseTaskLine(line, at: i) {
                blocks.append(NoteBlock(kind: .todo(isChecked: task.isChecked), text: task.text))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                let text = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                blocks.append(NoteBlock(kind: .quote, text: text))
                i += 1
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(NoteBlock(kind: .bullet, text: text))
                i += 1
                continue
            }

            // Paragraph
            blocks.append(NoteBlock(kind: .paragraph, text: line))
            i += 1
        }
        return blocks.isEmpty ? [NoteBlock(kind: .paragraph, text: "")] : blocks
    }

    /// Converts Notion-style blocks back into standard Markdown string.
    public static func blocksToMarkdown(_ blocks: [NoteBlock]) -> String {
        var lines: [String] = []
        for block in blocks {
            switch block.kind {
            case .heading(let level):
                let hashes = String(repeating: "#", count: level)
                lines.append("\(hashes) \(block.text)")
            case .todo(let isChecked):
                let mark = isChecked ? "[x]" : "[]"
                lines.append("- \(mark) \(block.text)")
            case .bullet:
                lines.append("- \(block.text)")
            case .quote:
                lines.append("> \(block.text)")
            case .code(let lang):
                lines.append("```\(lang)\n\(block.text)\n```")
            case .paragraph:
                lines.append(block.text)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Detects if user typing creates a markdown prefix trigger like `[] `, `# `, `- `, etc.
    /// Returns the converted block kind and the stripped remaining text.
    public static func detectLiveTransform(from input: String) -> (kind: NoteBlockKind, remainder: String)? {
        if input.hasPrefix("[] ") || input.hasPrefix("[ ] ") {
            let dropCount = input.hasPrefix("[] ") ? 3 : 4
            return (.todo(isChecked: false), String(input.dropFirst(dropCount)))
        }
        if input.hasPrefix("[x] ") || input.hasPrefix("[X] ") {
            return (.todo(isChecked: true), String(input.dropFirst(4)))
        }
        if input.hasPrefix("- [] ") || input.hasPrefix("- [ ] ") {
            let dropCount = input.hasPrefix("- [] ") ? 5 : 6
            return (.todo(isChecked: false), String(input.dropFirst(dropCount)))
        }
        if input.hasPrefix("- [x] ") || input.hasPrefix("- [X] ") {
            return (.todo(isChecked: true), String(input.dropFirst(6)))
        }
        if input.hasPrefix("# ") {
            return (.heading(level: 1), String(input.dropFirst(2)))
        }
        if input.hasPrefix("## ") {
            return (.heading(level: 2), String(input.dropFirst(3)))
        }
        if input.hasPrefix("### ") {
            return (.heading(level: 3), String(input.dropFirst(4)))
        }
        if input.hasPrefix("- ") || input.hasPrefix("* ") {
            return (.bullet, String(input.dropFirst(2)))
        }
        if input.hasPrefix("> ") {
            return (.quote, String(input.dropFirst(2)))
        }
        return nil
    }
}

// MARK: - Notes Layout (Height override for islandSize)

public enum NotesLayout {
    public nonisolated(unsafe) static var height: CGFloat? = 440
}

// MARK: - Notes Store

@MainActor
public final class NotesStore: ObservableObject {
    public static let shared = NotesStore()

    private let userDefaultsKey = "notchbuddy.notes.items"
    private let activeNoteIdKey = "notchbuddy.notes.activeId"
    private let heightKey = "notchbuddy.notes.preferredHeight"

    @Published public var currentHeight: CGFloat = 440

    @Published public var notes: [NoteItem] = [] {
        didSet {
            saveToDisk()
        }
    }

    @Published public var activeNoteId: UUID? {
        didSet {
            UserDefaults.standard.set(activeNoteId?.uuidString, forKey: activeNoteIdKey)
        }
    }

    public var activeNote: NoteItem? {
        if let id = activeNoteId, let found = notes.first(where: { $0.id == id }) {
            return found
        }
        return notes.first
    }

    public var hasUncheckedTasks: Bool {
        guard let note = activeNote else { return false }
        let lines = note.content.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            if let task = NotesMarkdownEngine.parseTaskLine(line, at: idx), !task.isChecked {
                return true
            }
        }
        return false
    }

    public var taskStats: (completed: Int, total: Int) {
        guard let note = activeNote else { return (0, 0) }
        let lines = note.content.components(separatedBy: "\n")
        var done = 0
        var total = 0
        for (idx, line) in lines.enumerated() {
            if let task = NotesMarkdownEngine.parseTaskLine(line, at: idx) {
                total += 1
                if task.isChecked { done += 1 }
            }
        }
        return (done, total)
    }

    public init() {
        loadFromDisk()
    }

    // MARK: - Actions

    public func createNote(title: String = "Untitled Note", content: String = "") -> NoteItem {
        let newNote = NoteItem(
            id: UUID(),
            title: title.isEmpty ? "Note \(notes.count + 1)" : title,
            content: content,
            createdAt: Date(),
            updatedAt: Date()
        )
        notes.append(newNote)
        activeNoteId = newNote.id
        return newNote
    }

    public func updateActiveNoteContent(_ newContent: String) {
        guard let note = activeNote, let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx].content = newContent
        notes[idx].updatedAt = Date()
    }

    public func updateActiveNoteTitle(_ newTitle: String) {
        guard let note = activeNote, let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[idx].title = clean.isEmpty ? "Untitled Note" : clean
        notes[idx].updatedAt = Date()
    }

    public func deleteNote(id: UUID) {
        guard notes.count > 1 else {
            // Keep at least 1 note; just clear it
            if let idx = notes.firstIndex(where: { $0.id == id }) {
                notes[idx].title = "Quick Notes"
                notes[idx].content = ""
                notes[idx].updatedAt = Date()
            }
            return
        }
        notes.removeAll { $0.id == id }
        if activeNoteId == id {
            activeNoteId = notes.first?.id
        }
    }

    /// Toggles the checkbox at the specified line in the active note.
    public func toggleCheckbox(atLine lineIndex: Int) {
        guard let note = activeNote else { return }
        var lines = note.content.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return }

        let originalLine = lines[lineIndex]
        let toggled = NotesMarkdownEngine.toggleCheckboxLine(originalLine)
        if toggled != originalLine {
            lines[lineIndex] = toggled
            updateActiveNoteContent(lines.joined(separator: "\n"))
        }
    }

    /// Cycles island height between 340, 440, and 500.
    public func cycleHeight() {
        let options: [CGFloat] = [340, 440, 500]
        let current = currentHeight
        let nextIdx = ((options.firstIndex(of: current) ?? 1) + 1) % options.count
        setHeight(options[nextIdx])
    }

    public func setHeight(_ h: CGFloat) {
        currentHeight = h
        NotesLayout.height = h
        UserDefaults.standard.set(Double(h), forKey: heightKey)
        NotificationCenter.default.post(name: Notification.Name("notchBuddy.notesHeightChanged"), object: nil)
    }

    /// Appends a new checkbox task to the active note.
    public func appendTaskItem(text: String = "New task") {
        guard let note = activeNote else { return }
        let item = "\n- [] \(text)"
        let updated = note.content.isEmpty ? "- [] \(text)" : "\(note.content)\(item)"
        updateActiveNoteContent(updated)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadFromDisk() {
        let savedHeight = UserDefaults.standard.double(forKey: heightKey)
        if savedHeight >= 300 {
            self.currentHeight = CGFloat(savedHeight)
            NotesLayout.height = CGFloat(savedHeight)
        } else {
            self.currentHeight = 440
            NotesLayout.height = 440
        }

        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([NoteItem].self, from: data),
           !saved.isEmpty {
            self.notes = saved
            if let activeStr = UserDefaults.standard.string(forKey: activeNoteIdKey),
               let activeUUID = UUID(uuidString: activeStr),
               saved.contains(where: { $0.id == activeUUID }) {
                self.activeNoteId = activeUUID
            } else {
                self.activeNoteId = saved.first?.id
            }
            return
        }

        // Initial default welcome note with interactive checkboxes
        let welcome = NoteItem(
            id: UUID(),
            title: "Quick Notes",
            content: """
            # Coucou Notes & Tasks

            - [] Review pull request
            - [x] Launch Coucou in notch
            - [] Click this checkbox to toggle!

            ## Markdown Features
            - **Bold text**, *italic*, and `inline code`
            - Headings (#, ##, ###)
            - Type `[]` anywhere to create an interactive checkbox!

            ```swift
            // Code blocks render automatically
            let greeting = "Hello from Mochi!"
            ```
            """,
            createdAt: Date(),
            updatedAt: Date()
        )
        self.notes = [welcome]
        self.activeNoteId = welcome.id
    }
}
