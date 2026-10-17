import Foundation

// MARK: - Pouch store (pure logic, tested by scripts/test-pouch-store.sh)

/// A file waiting in the pouch. The pouch keeps a reference only: the file is never copied or moved.
struct PouchItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    var pinned: Bool
}

/// The pouch shelf: files dropped on the notch, in drop order, each one once.
struct PouchStore: Equatable, Sendable {
    private(set) var items: [PouchItem] = []

    var pinned: [PouchItem] { items.filter(\.pinned) }

    /// Adds every URL not already here (same standardized path = same file).
    mutating func add(_ urls: [URL], pinned: Bool = false) {
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !items.contains(where: { $0.url.standardizedFileURL.path == path }) else { continue }
            items.append(PouchItem(id: UUID(), url: url, pinned: pinned))
        }
    }

    mutating func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
    }

    mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// A drag out of Coucou landed: the unpinned files it carried leave, pinned ones stay.
    mutating func removeAfterDragOut(_ ids: [UUID]) {
        items.removeAll { ids.contains($0.id) && !$0.pinned }
    }

    /// Drops the files `exists` no longer finds.
    mutating func prune(exists: (URL) -> Bool) {
        items.removeAll { !exists($0.url) }
    }
}

#if !APPSTORE
import Combine

// MARK: - Pouch (the app's one pouch)

/// The store plus what lives outside it: the Settings switch, pinned files kept across
/// relaunch as bookmarks, and files deleted or moved since they were dropped.
/// Unpinned files are memory only, so they clear on quit.
@MainActor
final class Pouch: ObservableObject {
    static let shared = Pouch()

    /// Settings › "Drops go to the pouch". Off: drops behave as before.
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "pouchEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "pouchEnabled") }
    }

    @Published var store = PouchStore() {
        didSet { if store.pinned != oldValue.pinned { savePinned() } }
    }

    private init() {
        let saved = UserDefaults.standard.array(forKey: "pouchPinned") as? [Data] ?? []
        let urls = saved.compactMap { data -> URL? in
            var stale = false
            return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        }
        store.add(urls, pinned: true)
        prune()
    }

    /// Files deleted or moved away since they were dropped leave the pouch.
    func prune() {
        store.prune { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func savePinned() {
        let bookmarks = store.pinned.compactMap { try? $0.url.bookmarkData() }
        UserDefaults.standard.set(bookmarks, forKey: "pouchPinned")
    }
}
#endif
