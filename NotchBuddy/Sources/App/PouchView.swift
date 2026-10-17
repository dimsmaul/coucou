#if !APPSTORE
import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI

/// The pouch card: files dropped on the notch wait here, by reference, until dragged out.
/// Click selects, ⌘-click adds to the selection, double click opens Quick Look; dragging a
/// selected file drags the whole selection.
@MainActor
struct PouchView: View {
    @ObservedObject private var pouch = Pouch.shared
    @State private var selection: Set<UUID> = []
    @State private var thumbnails: [URL: NSImage] = [:]
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            if pouch.store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(Color(hex: "#6B7280"))
                    Text(verbatim: String(localized: "Drop files here"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "#9398A1"))
                    Text(verbatim: String(localized: "Files dropped on the notch wait here"))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, 70)
                .transition(.opacity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(pouch.store.items) { item in
                            PouchTileView(
                                item: item,
                                isSelected: selection.contains(item.id),
                                thumbnail: thumbnails[item.url],
                                onSelect: { adding in select(item.id, adding: adding) },
                                onQuickLook: { PouchQuickLook.shared.show(item.url) },
                                onTogglePin: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        pouch.store.togglePin(item.id)
                                    }
                                },
                                onRemove: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        selection.remove(item.id)
                                        pouch.store.remove(item.id)
                                    }
                                },
                                getDragItems: { dragged(from: item) }
                            )
                            .onAppear { loadThumbnail(item.url) }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.4).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                }
                .padding(.leading, 98)
                .padding(.trailing, 16)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: pouch.store.items)
            }
        }
        .onAppear { pouch.prune() }
    }

    private func loadThumbnail(_ url: URL) {
        guard thumbnails[url] == nil else { return }
        PouchThumbnail.make(url, size: CGSize(width: 84, height: 84), scale: displayScale) { thumbnails[url] = $0 }
    }

    /// A selected file drags the whole selection; an unselected one drags alone.
    private func dragged(from item: PouchItem) -> [PouchItem] {
        guard selection.contains(item.id) else { return [item] }
        return pouch.store.items.filter { selection.contains($0.id) }
    }

    private func select(_ id: UUID, adding: Bool) {
        if !adding { selection = [id] }
        else if selection.contains(id) { selection.remove(id) }
        else { selection.insert(id) }
    }
}

// MARK: - Individual File Tile

/// A single file tile in the pouch shelf.
/// Owns its hover state locally so buttons never jump or show on other tiles.
@MainActor
private struct PouchTileView: View {
    let item: PouchItem
    let isSelected: Bool
    let thumbnail: NSImage?
    let onSelect: @MainActor @Sendable (Bool) -> Void
    let onQuickLook: @MainActor @Sendable () -> Void
    let onTogglePin: @MainActor @Sendable () -> Void
    let onRemove: @MainActor @Sendable () -> Void
    let getDragItems: @MainActor @Sendable () -> [PouchItem]

    @State private var isHovered = false
    @State private var isDeleting = false

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 5) {
            preview
                .frame(width: 84, height: 84)
                .background(Color.white.opacity(0.06))
                .clipShape(card)
                .overlay(card.stroke(borderColor, lineWidth: 1))
                .overlay(
                    PouchDragSource(
                        items: getDragItems,
                        onClick: onSelect,
                        onDoubleClick: onQuickLook
                    )
                )
                .overlay(alignment: .topTrailing) {
                    if isHovered || item.pinned {
                        HStack(spacing: 4) {
                            if isHovered || item.pinned {
                                roundButton(item.pinned ? "pin.fill" : "pin") {
                                    onTogglePin()
                                }
                            }
                            if isHovered {
                                roundButton("xmark") {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                        isDeleting = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                        onRemove()
                                    }
                                }
                            }
                        }
                        .padding(5)
                        .transition(.opacity)
                    }
                }
                .scaleEffect(isDeleting ? 0.3 : (isSelected ? 1.04 : (isHovered ? 1.02 : 1.0)))
                .opacity(isDeleting ? 0.0 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDeleting)

            Text(verbatim: item.url.lastPathComponent)
                .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : Color(hex: "#D5D7DB"))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 84)
                .opacity(isDeleting ? 0.0 : 1.0)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = inside
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)
        }
    }

    private var borderColor: Color {
        if item.pinned {
            return Color(hex: "#F5A524").opacity(isSelected ? 0.95 : 0.7)
        }
        if isSelected {
            return Color.white.opacity(0.5)
        }
        if isHovered {
            return Color.white.opacity(0.25)
        }
        return Color.white.opacity(0.12)
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.black.opacity(0.7)))
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

private enum PouchThumbnail {
    /// Quick Look renders off the main thread; `done` gets the image on the main actor.
    static func make(_ url: URL, size: CGSize, scale: CGFloat,
                     done: @escaping @MainActor @Sendable (NSImage) -> Void) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                                   representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            // NSImage isn't Sendable in the SDK; Quick Look hands it over and never touches it again.
            nonisolated(unsafe) let image = representation?.nsImage
            Task { @MainActor in if let image { done(image) } }
        }
    }
}

/// The island is a non-activating panel, so no responder there takes Quick Look control:
/// this object feeds the shared panel directly and stays alive as its data source.
@MainActor
private final class PouchQuickLook: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = PouchQuickLook()
    private var url: URL?

    func show(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        self.url = url
        panel.dataSource = self
        panel.reloadData()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url as NSURL?
    }
}

// MARK: - Drag out

private struct PouchDragSource: NSViewRepresentable {
    let items: @MainActor () -> [PouchItem]
    let onClick: @MainActor (_ commandHeld: Bool) -> Void
    var onDoubleClick: @MainActor () -> Void = {}

    func makeNSView(context: Context) -> PouchDragSourceView { PouchDragSourceView() }

    func updateNSView(_ view: PouchDragSourceView, context: Context) {
        view.items = items
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
    }
}

/// Drags pouch files to other apps. The destination copies them (moves them with ⌘ held,
/// like Finder); once a drop lands, the unpinned files it carried leave the pouch.
/// FileDropNSView ignores drags from this view, so they never count as a new drop.
final class PouchDragSourceView: NSView, NSDraggingSource {
    var items: @MainActor () -> [PouchItem] = { [] }
    var onClick: @MainActor (Bool) -> Void = { _ in }
    var onDoubleClick: @MainActor () -> Void = {}
    private var mouseDownEvent: NSEvent?
    private var dragged: [UUID] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

    /// The first click of a double click already selected; the second opens Quick Look.
    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil {
            if event.clickCount == 2 { onDoubleClick() } else { onClick(event.modifierFlags.contains(.command)) }
        }
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent,
              hypot(event.locationInWindow.x - down.locationInWindow.x,
                    event.locationInWindow.y - down.locationInWindow.y) > 3 else { return }
        mouseDownEvent = nil
        let files = items()
        guard !files.isEmpty else { return }
        dragged = files.map(\.id)
        let origin = convert(down.locationInWindow, from: nil)
        let dragItems = files.enumerated().map { i, file in
            let item = NSDraggingItem(pasteboardWriter: file.url as NSURL)
            let shift = CGFloat(min(i, 4)) * 4
            item.setDraggingFrame(NSRect(x: origin.x - 16 + shift, y: origin.y - 16 - shift, width: 32, height: 32),
                                  contents: NSWorkspace.shared.icon(forFile: file.url.path))
            return item
        }
        beginDraggingSession(with: dragItems, event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication else { return [] }
        return NSEvent.modifierFlags.contains(.command) ? .move : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        // A cancelled drag (no operation) changes nothing.
        guard !operation.isEmpty else { return }
        Pouch.shared.store.removeAfterDragOut(dragged)
    }
}

// MARK: - Compact badge

/// Compact island: a paperclip and how many files wait in the pouch; tapping opens it.
/// Nothing at all when the switch is off or the pouch is empty.
struct PouchBadge: View {
    @ObservedObject private var pouch = Pouch.shared

    var body: some View {
        if pouch.isEnabled && !pouch.store.items.isEmpty {
            Button {
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.pouch)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "paperclip")
                    Text(verbatim: "\(pouch.store.items.count)")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "#D5D7DB"))
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
