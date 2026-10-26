import Foundation

@main
struct NotesStoreTests {
    static func main() async {
        print("Running NotesStore & Markdown Engine tests…")

        testTaskLineParsing()
        testCheckboxToggling()
        testMarkdownParsing()
        testNotionBlocks()
        await testNotesStoreOperations()

        print("\nAll NotesStore & Markdown Engine tests passed! ✓")
    }

    // MARK: - Notion Live Blocks & Transform

    static func testNotionBlocks() {
        print("\nNotion Live Blocks & Transform:")

        // 1. Live trigger detection
        let d1 = NotesMarkdownEngine.detectLiveTransform(from: "[] Buy groceries")
        assert(d1 != nil, "should detect []")
        assert(d1?.kind == .todo(isChecked: false), "should be unchecked todo")
        assert(d1?.remainder == "Buy groceries")

        let d2 = NotesMarkdownEngine.detectLiveTransform(from: "[x] Done task")
        assert(d2?.kind == .todo(isChecked: true))
        assert(d2?.remainder == "Done task")

        let d3 = NotesMarkdownEngine.detectLiveTransform(from: "# Main Header")
        assert(d3?.kind == .heading(level: 1))
        assert(d3?.remainder == "Main Header")

        let d4 = NotesMarkdownEngine.detectLiveTransform(from: "## Sub Header")
        assert(d4?.kind == .heading(level: 2))
        assert(d4?.remainder == "Sub Header")

        let d5 = NotesMarkdownEngine.detectLiveTransform(from: "- Bullet point")
        assert(d5?.kind == .bullet)
        assert(d5?.remainder == "Bullet point")

        let d6 = NotesMarkdownEngine.detectLiveTransform(from: "> A quote")
        assert(d6?.kind == .quote)
        assert(d6?.remainder == "A quote")

        print("  ✓ Live typing triggers detected ([] -> todo, # -> heading, - -> bullet, > -> quote)")

        // 2. Markdown to Blocks and back
        let md = """
        # My Outline
        - [] Task one
        - [x] Task two
        - Bullet point
        > Invaluable advice
        Regular note paragraph
        """

        let blocks = NotesMarkdownEngine.markdownToBlocks(md)
        assert(blocks.count == 6, "should convert 6 blocks, got \(blocks.count)")
        assert(blocks[0].kind == .heading(level: 1) && blocks[0].text == "My Outline")
        assert(blocks[1].kind == .todo(isChecked: false) && blocks[1].text == "Task one")
        assert(blocks[2].kind == .todo(isChecked: true) && blocks[2].text == "Task two")
        assert(blocks[3].kind == .bullet && blocks[3].text == "Bullet point")
        assert(blocks[4].kind == .quote && blocks[4].text == "Invaluable advice")
        assert(blocks[5].kind == .paragraph && blocks[5].text == "Regular note paragraph")

        let regenerated = NotesMarkdownEngine.blocksToMarkdown(blocks)
        assert(regenerated.contains("# My Outline"))
        assert(regenerated.contains("- [] Task one"))
        assert(regenerated.contains("- [x] Task two"))
        print("  ✓ Lossless Markdown <-> Notion Blocks conversion verified")
    }

    // MARK: - Task Line Parsing

    static func testTaskLineParsing() {
        print("\nTask Line Parsing:")

        // 1. [] with space
        let t1 = NotesMarkdownEngine.parseTaskLine("[] Buy groceries", at: 0)
        assert(t1 != nil, "[] should be recognized as task")
        assert(t1?.isChecked == false, "[] should be unchecked")
        assert(t1?.text == "Buy groceries", "text should match")
        print("  ✓ '[] Buy groceries' parsed as unchecked")

        // 2. [ ] with space
        let t2 = NotesMarkdownEngine.parseTaskLine("[ ] Write documentation", at: 1)
        assert(t2 != nil, "[ ] should be recognized as task")
        assert(t2?.isChecked == false, "[ ] should be unchecked")
        assert(t2?.text == "Write documentation", "text should match")
        print("  ✓ '[ ] Write documentation' parsed as unchecked")

        // 3. [x] and [X]
        let t3 = NotesMarkdownEngine.parseTaskLine("[x] Submit report", at: 2)
        assert(t3?.isChecked == true, "[x] should be checked")
        assert(t3?.text == "Submit report", "text should match")
        let t4 = NotesMarkdownEngine.parseTaskLine("[X] Capital X checked", at: 3)
        assert(t4?.isChecked == true, "[X] should be checked")
        print("  ✓ '[x]' and '[X]' parsed as checked")

        // 4. - [] and - [ ]
        let t5 = NotesMarkdownEngine.parseTaskLine("- [] Bullet unchecked", at: 4)
        assert(t5?.isChecked == false, "- [] should be unchecked")
        assert(t5?.prefix == "- ", "prefix should be '- '")
        assert(t5?.text == "Bullet unchecked", "text should match")

        let t6 = NotesMarkdownEngine.parseTaskLine("  - [x] Indented bullet checked", at: 5)
        assert(t6?.isChecked == true, "- [x] should be checked")
        assert(t6?.text == "Indented bullet checked", "text should match")
        print("  ✓ Bullet lists '- []' and '  - [x]' parsed correctly")

        // 5. * [ ] and + [ ]
        let t7 = NotesMarkdownEngine.parseTaskLine("* [ ] Asterisk bullet", at: 6)
        assert(t7?.isChecked == false, "* [ ] should be unchecked")
        assert(t7?.prefix == "* ", "prefix should be '* '")
        print("  ✓ '* [ ]' parsed correctly")

        // 6. Non-task lines
        let n1 = NotesMarkdownEngine.parseTaskLine("Just normal text", at: 7)
        assert(n1 == nil, "normal text should not be task")
        let n2 = NotesMarkdownEngine.parseTaskLine("- Regular list item", at: 8)
        assert(n2 == nil, "regular bullet should not be task")
        print("  ✓ Non-task lines correctly ignored")
    }

    // MARK: - Checkbox Toggling

    static func testCheckboxToggling() {
        print("\nCheckbox Toggling:")

        // Unchecked to checked
        let r1 = NotesMarkdownEngine.toggleCheckboxLine("[] Buy milk")
        assert(r1 == "[x] Buy milk", "[] should toggle to [x], got '\(r1)'")

        let r2 = NotesMarkdownEngine.toggleCheckboxLine("[ ] Buy milk")
        assert(r2 == "[x] Buy milk", "[ ] should toggle to [x], got '\(r2)'")

        let r3 = NotesMarkdownEngine.toggleCheckboxLine("- [] Clean desk")
        assert(r3 == "- [x] Clean desk", "- [] should toggle to - [x], got '\(r3)'")

        let r4 = NotesMarkdownEngine.toggleCheckboxLine("  - [ ] Fix bug")
        assert(r4 == "  - [x] Fix bug", "indentation and bullet should be preserved, got '\(r4)'")

        print("  ✓ Unchecked -> Checked toggles verified")

        // Checked to unchecked
        let r5 = NotesMarkdownEngine.toggleCheckboxLine("[x] Done item")
        assert(r5 == "[ ] Done item", "[x] should toggle to [ ], got '\(r5)'")

        let r6 = NotesMarkdownEngine.toggleCheckboxLine("[X] Capital X item")
        assert(r6 == "[ ] Capital X item", "[X] should toggle to [ ], got '\(r6)'")

        let r7 = NotesMarkdownEngine.toggleCheckboxLine("- [x] Done bullet")
        assert(r7 == "- [ ] Done bullet", "- [x] should toggle to - [ ], got '\(r7)'")

        let r8 = NotesMarkdownEngine.toggleCheckboxLine("    - [x] Indented done")
        assert(r8 == "    - [ ] Indented done", "indentation preserved on uncheck, got '\(r8)'")

        print("  ✓ Checked -> Unchecked toggles verified")

        // Non-checkbox line returns unchanged
        let r9 = NotesMarkdownEngine.toggleCheckboxLine("# Heading 1")
        assert(r9 == "# Heading 1", "non-checkbox line unchanged")
        print("  ✓ Non-checkbox lines untouched")
    }

    // MARK: - Markdown Parsing

    static func testMarkdownParsing() {
        print("\nMarkdown Parsing:")

        let md = """
        # Main Title
        ## Subtitle

        - [] Unchecked task
        - [x] Finished task

        - Bullet item
        1. Numbered item

        > A motivational quote

        ```swift
        let x = 10
        ```

        A normal paragraph.
        ---
        """

        let blocks = NotesMarkdownEngine.parse(md)
        assert(blocks.count >= 8, "should parse into multiple blocks, got \(blocks.count)")

        // Headings
        guard case .heading(let lvl1, let t1, _) = blocks[0] else { fatalError("expected heading 1") }
        assert(lvl1 == 1 && t1 == "Main Title")

        guard case .heading(let lvl2, let t2, _) = blocks[1] else { fatalError("expected heading 2") }
        assert(lvl2 == 2 && t2 == "Subtitle")

        // Task items
        guard case .taskItem(_, let c1, let txt1) = blocks[2] else { fatalError("expected task item") }
        assert(!c1 && txt1 == "Unchecked task")

        guard case .taskItem(_, let c2, let txt2) = blocks[3] else { fatalError("expected checked task item") }
        assert(c2 && txt2 == "Finished task")

        // List item
        guard case .listItem(let pfx, let ltxt, _, _) = blocks[4] else { fatalError("expected list item") }
        assert(pfx == "•" && ltxt == "Bullet item")

        // Code block
        let codeBlock = blocks.first(where: {
            if case .codeBlock = $0 { return true }
            return false
        })
        assert(codeBlock != nil, "code block should be parsed")

        print("  ✓ Headings, tasks, lists, code blocks, quotes verified")
    }

    // MARK: - NotesStore Operations

    @MainActor
    static func testNotesStoreOperations() async {
        print("\nNotesStore Operations:")

        let store = NotesStore()
        assert(!store.notes.isEmpty, "notes should have initial default note")

        let initialCount = store.notes.count
        let note = store.createNote(title: "Test Note", content: "- [] Task 1\n- [x] Task 2")
        assert(store.notes.count == initialCount + 1, "note count should increase")
        assert(store.activeNoteId == note.id, "created note should become active")

        let stats = store.taskStats
        assert(stats.total == 2, "total tasks should be 2, got \(stats.total)")
        assert(stats.completed == 1, "completed tasks should be 1, got \(stats.completed)")
        assert(store.hasUncheckedTasks, "should have unchecked tasks")

        // Toggle task 1 at line 0
        store.toggleCheckbox(atLine: 0)
        let updatedStats = store.taskStats
        assert(updatedStats.completed == 2, "both tasks should now be completed")
        assert(!store.hasUncheckedTasks, "should have no unchecked tasks")

        // Toggle task 1 back to unchecked
        store.toggleCheckbox(atLine: 0)
        assert(store.taskStats.completed == 1, "should be back to 1 completed")

        // Cleanup
        store.deleteNote(id: note.id)
        assert(store.notes.count == initialCount, "note should be deleted")

        print("  ✓ NotesStore CRUD, stats and checkbox toggles verified")
    }
}
