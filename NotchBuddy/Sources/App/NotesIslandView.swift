import AppKit
import SwiftUI

// MARK: - Unified Markdown Text View (AppKit Single Document Canvas)

final class UnifiedMarkdownTextView: NSTextView {
    var onContentChange: ((String) -> Void)?
    var onToggleCheckbox: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        setupDefaults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDefaults()
    }

    private func setupDefaults() {
        isRichText = false
        allowsUndo = true
        isContinuousSpellCheckingEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        font = NSFont.systemFont(ofSize: 12.5)
        textColor = NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.94, alpha: 1.0)
        insertionPointColor = NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.20, alpha: 1.0)
        backgroundColor = .clear
        drawsBackground = false
        textContainerInset = NSSize(width: 6, height: 6)
        isHorizontallyResizable = false
        isVerticallyResizable = true
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0
    }

    // MARK: - Interactive Checkbox Mouse Click

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        let nsString = (string as NSString)

        if charIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineStr = nsString.substring(with: lineRange)
            let offsetInLine = charIndex - lineRange.location

            // If user clicked within the first ~7 characters of a task line, toggle the checkbox!
            if offsetInLine <= 7, let _ = NotesMarkdownEngine.parseTaskLine(lineStr, at: 0) {
                let toggled = NotesMarkdownEngine.toggleCheckboxLine(lineStr)
                if toggled != lineStr {
                    if let textStorage = textStorage {
                        textStorage.replaceCharacters(in: lineRange, with: toggled)
                        didChangeText()
                        SoundEngine.shared.play("tick")
                        applyMarkdownSyntaxHighlighting()
                        onContentChange?(string)
                        onToggleCheckbox?()
                        return
                    }
                }
            }
        }

        super.mouseDown(with: event)
    }

    // MARK: - Smart Return Key (Auto-continuation for lists & checkboxes)

    override func insertNewline(_ sender: Any?) {
        let selectedRange = self.selectedRange()
        let nsString = (string as NSString)

        if selectedRange.location <= nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
            let currentLine = nsString.substring(with: lineRange)
            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)

            // If empty task marker on current line, clear it and leave an empty line
            if trimmed == "- []" || trimmed == "- [ ]" || trimmed == "[]" || trimmed == "[ ]" || trimmed == "- [x]" || trimmed == "- [X]" {
                let hasNewline = currentLine.hasSuffix("\n")
                let replaceLength = hasNewline ? currentLine.count - 1 : currentLine.count
                textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: replaceLength), with: "")
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
                didChangeText()
                applyMarkdownSyntaxHighlighting()
                onContentChange?(string)
                return
            }

            // If user was on a task item with text: "- [ ] Buy milk", pressing Enter continues "- [ ] "
            if let task = NotesMarkdownEngine.parseTaskLine(currentLine, at: 0) {
                super.insertNewline(sender)
                let prefix = task.prefix.isEmpty ? "- [ ] " : "\(task.prefix)[ ] "
                insertText(prefix, replacementRange: self.selectedRange())
                applyMarkdownSyntaxHighlighting()
                onContentChange?(string)
                return
            }

            // If empty bullet "- ", clear it
            if trimmed == "-" || trimmed == "*" || trimmed == "•" {
                let hasNewline = currentLine.hasSuffix("\n")
                let replaceLength = hasNewline ? currentLine.count - 1 : currentLine.count
                textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: replaceLength), with: "")
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
                didChangeText()
                applyMarkdownSyntaxHighlighting()
                onContentChange?(string)
                return
            }

            // If bullet list item, continue bullet
            if currentLine.hasPrefix("- ") || currentLine.hasPrefix("* ") {
                let prefix = String(currentLine.prefix(2))
                super.insertNewline(sender)
                insertText(prefix, replacementRange: self.selectedRange())
                applyMarkdownSyntaxHighlighting()
                onContentChange?(string)
                return
            }
        }

        super.insertNewline(sender)
        applyMarkdownSyntaxHighlighting()
        onContentChange?(string)
    }

    // MARK: - Live Syntax Highlighting (Runs on NSTextStorage in real time)

    func applyMarkdownSyntaxHighlighting() {
        guard let textStorage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return }

        let nsString = textStorage.string as NSString

        textStorage.beginEditing()

        // 1. Base style for all text
        let baseFont = NSFont.systemFont(ofSize: 12.5)
        let baseColor = NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.94, alpha: 1.0)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 3

        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: paraStyle
        ], range: fullRange)

        // 2. Line by line styling
        var lineStart = 0
        while lineStart < fullRange.length {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineStr = nsString.substring(with: lineRange)
            let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("# ") {
                textStorage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15.5), range: lineRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.white, range: lineRange)
            } else if trimmed.hasPrefix("## ") {
                textStorage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14.0), range: lineRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.96, alpha: 1.0), range: lineRange)
            } else if trimmed.hasPrefix("### ") {
                textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13.0, weight: .semibold), range: lineRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.94, alpha: 1.0), range: lineRange)
            } else if let task = NotesMarkdownEngine.parseTaskLine(lineStr, at: 0) {
                if task.isChecked {
                    textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.50, alpha: 1.0), range: lineRange)
                } else {
                    // Highlight the checkbox marker in emerald green
                    if let range = lineStr.range(of: "[ ]") ?? lineStr.range(of: "[]") {
                        let nsRange = NSRange(range, in: lineStr)
                        let markerRange = NSRange(location: lineRange.location + nsRange.location, length: nsRange.length)
                        textStorage.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.15, green: 0.85, blue: 0.55, alpha: 1.0), range: markerRange)
                        textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold), range: markerRange)
                    }
                }
            } else if trimmed.hasPrefix("> ") {
                let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12.5), toHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: italicFont, range: lineRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.96, green: 0.68, blue: 0.25, alpha: 1.0), range: lineRange)
            }

            lineStart = lineRange.location + lineRange.length
        }

        // 3. Inline bold: **text**
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*", options: []) {
            let matches = regex.matches(in: nsString as String, options: [], range: fullRange)
            for m in matches {
                textStorage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12.5), range: m.range)
            }
        }

        // 4. Inline code: `text`
        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            let matches = regex.matches(in: nsString as String, options: [], range: fullRange)
            for m in matches {
                textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular), range: m.range)
                textStorage.addAttribute(.backgroundColor, value: NSColor(calibratedWhite: 1.0, alpha: 0.08), range: m.range)
            }
        }

        textStorage.endEditing()
    }
}

// MARK: - Unified Markdown Editor NSViewRepresentable

struct UnifiedMarkdownEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var onToggleCheckbox: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = UnifiedMarkdownTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.onContentChange = { newText in
            context.coordinator.parent.text = newText
        }
        textView.onToggleCheckbox = onToggleCheckbox
        textView.string = text
        textView.applyMarkdownSyntaxHighlighting()

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? UnifiedMarkdownTextView else { return }
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.applyMarkdownSyntaxHighlighting()
            if selectedRange.location <= (text as NSString).length {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: UnifiedMarkdownEditorRepresentable
        weak var textView: UnifiedMarkdownTextView?

        init(_ parent: UnifiedMarkdownEditorRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            let newText = tv.string
            parent.text = newText
            tv.applyMarkdownSyntaxHighlighting()
        }
    }
}

// MARK: - Notes Island View (Cohesive Document & Live Editor)

struct NotesIslandView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = NotesStore.shared

    enum NoteDisplayMode: String, CaseIterable {
        case outline = "Outline"
        case editor = "Edit"
    }

    @State private var mode: NoteDisplayMode = .outline
    @State private var copied = false
    @State private var showingNotePicker = false
    @State private var isEditingTitle = false
    @State private var titleDraft = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)

            VStack(alignment: .leading, spacing: 8) {
                headerRow
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.horizontal, 14)

                Group {
                    if mode == .outline {
                        renderedOutlineView
                    } else {
                        unifiedEditorView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            // Note title & selector
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#F59E0B"))

                if isEditingTitle {
                    TextField("Note title", text: $titleDraft, onCommit: {
                        store.updateActiveNoteTitle(titleDraft)
                        isEditingTitle = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .frame(width: 130)
                } else {
                    Button(action: { showingNotePicker.toggle() }) {
                        HStack(spacing: 4) {
                            Text(store.activeNote?.title ?? "Quick Notes")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "#F5F6F8"))
                                .lineLimit(1)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color(hex: "#8E939C"))
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingNotePicker, arrowEdge: .bottom) {
                        notesListPopover
                    }
                }
            }

            if !isEditingTitle {
                Button(action: {
                    titleDraft = store.activeNote?.title ?? ""
                    isEditingTitle = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                .help("Rename note")
            }

            Spacer(minLength: 4)

            // Task stats badge
            let stats = store.taskStats
            if stats.total > 0 {
                HStack(spacing: 4) {
                    Image(systemName: stats.completed == stats.total ? "checkmark.circle.fill" : "checklist")
                        .font(.system(size: 9))
                    Text("\(stats.completed)/\(stats.total) done")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(stats.completed == stats.total ? Color(hex: "#10B981").opacity(0.18) : Color.white.opacity(0.06))
                .foregroundColor(stats.completed == stats.total ? Color(hex: "#34D399") : Color(hex: "#8E939C"))
                .clipShape(Capsule())
            }

            // Mode toggle: Outline (Rendered MD) / Edit (Unified Editor)
            HStack(spacing: 2) {
                ForEach(NoteDisplayMode.allCases, id: \.self) { m in
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            mode = m
                            isEditingTitle = false
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: m == .outline ? "doc.plaintext" : "square.and.pencil")
                                .font(.system(size: 8))
                            Text(m.rawValue)
                                .font(.system(size: 9.5, weight: mode == m ? .semibold : .regular))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(mode == m ? Color.white.opacity(0.14) : Color.clear)
                        .foregroundColor(mode == m ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())

            // Copy markdown button
            Button(action: copyToClipboard) {
                HStack(spacing: 3) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    if copied {
                        Text("Copied")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundColor(copied ? Color(hex: "#34D399") : Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help("Copy markdown to clipboard")

            // Island size toggle button
            Button(action: {
                store.cycleHeight()
                SoundEngine.shared.play("tick")
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .help("Change island size: currently \(Int(store.currentHeight))pt (Click to cycle 340 / 440 / 500)")
        }
    }

    // MARK: - Rendered Outline View (Cohesive Document Surface)

    private var renderedOutlineView: some View {
        let content = store.activeNote?.content ?? ""
        let blocks = NotesMarkdownEngine.parse(content)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if blocks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "#5C6370"))
                        Text("This note is empty.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#8E939C"))

                        Button(action: {
                            withAnimation { mode = .editor }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.pencil")
                                Text("Start Writing")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: "#F59E0B").opacity(0.18))
                            .foregroundColor(Color(hex: "#F59E0B"))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(blocks) { block in
                        renderedBlockView(block: block)
                    }

                    // Floating footer button to edit
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation { mode = .editor }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 9))
                                Text("Edit Note")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.06))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Rendered Block Component

    @ViewBuilder
    private func renderedBlockView(block: NoteMDBlock) -> some View {
        switch block {
        case .heading(let level, let text, _):
            Text(text)
                .font(headingFont(level: level))
                .fontWeight(.bold)
                .foregroundColor(Color.white)
                .padding(.top, level == 1 ? 6 : 3)
                .padding(.bottom, 1)

        case .taskItem(let lineIndex, let isChecked, let text):
            HStack(alignment: .top, spacing: 8) {
                Button(action: {
                    store.toggleCheckbox(atLine: lineIndex)
                    SoundEngine.shared.play("tick")
                }) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isChecked ? Color(hex: "#10B981") : Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                .padding(.top, 1)

                Text(text)
                    .font(.system(size: 12.5))
                    .strikethrough(isChecked, color: Color(hex: "#6B7079"))
                    .foregroundColor(isChecked ? Color(hex: "#6B7079") : Color(hex: "#F5F6F8"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 1)

        case .listItem(let prefix, let text, let indent, _):
            HStack(alignment: .top, spacing: 6) {
                Text(prefix)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#8E939C"))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#E5E7EB"))
            }
            .padding(.leading, CGFloat(indent * 12))
            .padding(.vertical, 0.5)

        case .codeBlock(let lang, let code, _):
            VStack(alignment: .leading, spacing: 4) {
                if !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "#38BDF8"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .quote(let text, _):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color(hex: "#F59E0B"))
                    .frame(width: 2.5)
                    .clipShape(Capsule())
                Text(text)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundColor(Color(hex: "#E5E7EB"))
            }
            .padding(.vertical, 2)

        case .paragraph(let text, _):
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#D1D5DB"))
                .lineSpacing(2)

        case .rule:
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 2)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 15.5)
        case 2: return .system(size: 13.5)
        default: return .system(size: 12.5)
        }
    }

    // MARK: - Unified Editor View (Single NSTextView Document Canvas)

    private var unifiedEditorView: some View {
        VStack(spacing: 6) {
            UnifiedMarkdownEditorRepresentable(
                text: Binding(
                    get: { store.activeNote?.content ?? "" },
                    set: { store.updateActiveNoteContent($0) }
                ),
                onToggleCheckbox: {
                    // Triggers view refresh for stats badge
                }
            )
            .padding(6)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // Formatting helper bar
            HStack(spacing: 5) {
                insertHelperButton(label: "+ [] Checkbox", insert: "\n- [] ")
                insertHelperButton(label: "+ # Heading", insert: "\n# ")
                insertHelperButton(label: "+ • Bullet", insert: "\n- ")
                insertHelperButton(label: "+ **Bold**", insert: "**text**")
                insertHelperButton(label: "+ `Code`", insert: "`code`")

                Spacer()

                Button("Done") {
                    withAnimation { mode = .outline }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color(hex: "#10B981"))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color(hex: "#10B981").opacity(0.15))
                .clipShape(Capsule())
            }
            .padding(.top, 1)
        }
    }

    private func insertHelperButton(label: String, insert: String) -> some View {
        Button(action: {
            guard let note = store.activeNote else { return }
            let updated = note.content.isEmpty ? insert.trimmingCharacters(in: .whitespacesAndNewlines) : "\(note.content)\(insert)"
            store.updateActiveNoteContent(updated)
            SoundEngine.shared.play("blip")
        }) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.05))
                .foregroundColor(Color(hex: "#8E939C"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note Selector Popover

    private var notesListPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Your Notes")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#8E939C"))

                Spacer()

                Button(action: {
                    let created = store.createNote()
                    showingNotePicker = false
                    titleDraft = created.title
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                        Text("New")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#F59E0B"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider().background(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(store.notes) { note in
                        let isSelected = note.id == store.activeNoteId
                        Button(action: {
                            store.activeNoteId = note.id
                            showingNotePicker = false
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark" : "note.text")
                                    .font(.system(size: 9))
                                    .foregroundColor(isSelected ? Color(hex: "#F59E0B") : Color(hex: "#8E939C"))

                                Text(note.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                                    .lineLimit(1)

                                Spacer()

                                if store.notes.count > 1 {
                                    Button(action: {
                                        store.deleteNote(id: note.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 8.5))
                                            .foregroundColor(Color(hex: "#F4505E").opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 160)
        }
        .frame(width: 200)
        .background(Color(hex: "#141518"))
    }

    private func copyToClipboard() {
        guard let content = store.activeNote?.content else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        withAnimation { copied = true }
        SoundEngine.shared.play("blip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}
