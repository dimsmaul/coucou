import Foundation

@main
enum PouchStoreTests {

    static var failures = 0

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") }
        else      { print("  ✗ \(label)"); failures += 1 }
    }

    static func checkInt(_ label: String, _ got: Int, _ expected: Int) {
        if got == expected { print("  ✓ \(label)") }
        else { print("  ✗ \(label)  got: \(got)  expected: \(expected)"); failures += 1 }
    }

    static let a = URL(fileURLWithPath: "/tmp/pouch/a.pdf")
    static let b = URL(fileURLWithPath: "/tmp/pouch/b.png")
    static let c = URL(fileURLWithPath: "/tmp/pouch/c.txt")

    static func main() {

        // ── add — bulk ─────────────────────────────────────────────────────────
        print("PouchStore.add — bulk")
        do {
            var s = PouchStore()
            s.add([a, b, c])
            checkInt("3 items", s.items.count, 3)
            checkTrue("drop order kept", s.items.map(\.url) == [a, b, c])
            checkTrue("none pinned", s.pinned.isEmpty)
        }

        // ── add — dedupe ───────────────────────────────────────────────────────
        print("PouchStore.add — dedupe")
        do {
            var s = PouchStore()
            s.add([a, b])
            let firstId = s.items[0].id
            s.add([URL(fileURLWithPath: "/tmp/pouch/./sub/../a.pdf"), b, c])
            checkInt("same path once", s.items.count, 3)
            checkTrue("existing item kept", s.items[0].id == firstId)
            s.add([c, c])
            checkInt("duplicates in one drop", s.items.count, 3)
        }

        // ── togglePin ──────────────────────────────────────────────────────────
        print("PouchStore.togglePin")
        do {
            var s = PouchStore()
            s.add([a, b])
            s.togglePin(s.items[1].id)
            checkTrue("b pinned", s.items[1].pinned)
            checkTrue("pinned subset == [b]", s.pinned.map(\.url) == [b])
            s.togglePin(s.items[1].id)
            checkTrue("b unpinned again", s.pinned.isEmpty)
            s.togglePin(UUID())
            checkInt("unknown id: no change", s.items.count, 2)
        }

        // ── remove ─────────────────────────────────────────────────────────────
        print("PouchStore.remove")
        do {
            var s = PouchStore()
            s.add([a, b])
            s.togglePin(s.items[0].id)
            s.remove(s.items[0].id)
            checkTrue("pinned item removed by ×", s.items.map(\.url) == [b])
        }

        // ── removeAfterDragOut ─────────────────────────────────────────────────
        print("PouchStore.removeAfterDragOut")
        do {
            var s = PouchStore()
            s.add([a, b, c])
            s.togglePin(s.items[0].id)
            s.removeAfterDragOut(s.items.prefix(2).map(\.id))
            checkTrue("unpinned dragged item left", s.items.map(\.url) == [a, c])
            checkTrue("pinned dragged item stays", s.items[0].pinned)
        }

        // ── no drag-out keeps items ────────────────────────────────────────────
        print("PouchStore — cancelled drag")
        do {
            var s = PouchStore()
            s.add([a, b])
            let before = s
            s.removeAfterDragOut([])
            checkTrue("nothing removed", s == before)
        }

        // ── prune ──────────────────────────────────────────────────────────────
        print("PouchStore.prune")
        do {
            var s = PouchStore()
            s.add([a, b, c])
            s.togglePin(s.items[1].id)
            s.prune { $0 != b }
            checkTrue("missing file removed, pinned or not", s.items.map(\.url) == [a, c])
        }

        // ── finish ─────────────────────────────────────────────────────────────
        if failures == 0 {
            print("\nAll tests passed.")
            exit(0)
        } else {
            print("\n\(failures) test(s) failed.")
            exit(1)
        }
    }
}
