import AppKit
import SwiftUI
import SummonKit

/// The middle column: everything in the current sidebar selection, as a dense list
/// or a grid when the content is visual.
public struct ItemListView: View {
    @Bindable var model: AppModel
    let items: [ItemSnapshot]
    @State private var gridColumns = 1
    /// So a click hands the keyboard to the list. Without it, selecting with the
    /// mouse and then pressing an arrow key did nothing — focus was still wherever
    /// you left it, usually a text field in the detail pane.
    @FocusState private var listFocused: Bool

    public init(model: AppModel, items: [ItemSnapshot]) {
        self.model = model
        self.items = items
    }

    public var body: some View {
        Group {
            if case .clipboard = model.sidebarSelection {
                ClipboardListView(model: model)
            } else if items.isEmpty {
                emptyState
            } else if model.useGridLayout {
                grid
            } else {
                list
            }
        }
        // Whatever the list receives from outside lands in the folder being shown,
        // which is where a new item would go anyway. The delegate refuses Summon's
        // own drags: a row dragged over the empty space below the list still carries
        // its contents, and a content-based handler would duplicate it.
        .onDrop(of: [.fileURL, .text, SummonDragType.item, SummonDragType.folder],
                delegate: LibraryDropDelegate(model: model, folder: { currentFolder }))
    }

    /// Whether rows can be dragged into a hand-made order right now.
    ///
    /// A folder is the only view with an order of its own to write to, and only while
    /// nothing is typed — under a search the list is in rank order, so a row dropped
    /// into place would spring straight back.
    private var canReorder: Bool {
        if case .folder = model.sidebarSelection { return model.mainSearch.isEmpty }
        return false
    }

    /// Selecting always hands the keyboard to the list, so the mouse and the arrow
    /// keys drive the same thing instead of taking turns.
    private func select(_ id: UUID) {
        model.mainSelection = id
        listFocused = true
    }

    private var currentFolder: SummonFolder? {
        guard case .folder(let id) = model.sidebarSelection else { return nil }
        return model.store.folder(id: id)
    }

    /// The same construct the panel uses, not a `List`.
    ///
    /// `List(selection:)` paints the system accent behind the selected row — a
    /// saturated blue over the neutral fill the row already draws, which is far
    /// louder than anything else in a monochrome app and cannot be restyled. Owning
    /// the selection also ends the fight with `.onDrag`, which swallows the click a
    /// List uses to select.
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        ItemRow(model: model, item: item,
                                canReorder: canReorder, onSelect: select)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, Theme.Space.xs)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.upArrow) { model.moveMainSelection(by: -1); return .handled }
            .onKeyPress(.downArrow) { model.moveMainSelection(by: 1); return .handled }
            .onChange(of: model.mainSelection) { _, new in
                guard let new else { return }
                proxy.scrollTo(new)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.s)],
                      spacing: Theme.Space.s) {
                ForEach(items) { item in
                    ItemCard(model: model, item: item, isSelected: model.mainSelection == item.id)
                        .onTapGesture { model.mainSelection = item.id }
                }
            }
            .padding(Theme.Space.m)
        }
        // Measured on the scroll view, not with a GeometryReader wrapped around the
        // grid: a GeometryReader inside a ScrollView is greedy in the scroll axis and
        // leaves the content with no height to lay out in.
        .onGeometryChange(for: Int.self) { proxy in
            max(1, Int(proxy.size.width / (150 + Theme.Space.s)))
        } action: { gridColumns = $0 }
        // The grid was mouse-only: ItemCard had a tap gesture and nothing else, so a
        // whole view mode could not be reached from the keyboard. Up and down move a
        // full row, which is what "down" means in a grid.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { model.moveMainSelection(by: -gridColumns); return .handled }
        .onKeyPress(.downArrow) { model.moveMainSelection(by: gridColumns); return .handled }
        .onKeyPress(.leftArrow) { model.moveMainSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { model.moveMainSelection(by: 1); return .handled }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: emptySymbol,
            title: emptyTitle,
            message: emptyMessage,
            action: ("Add Files…", { model.presentImportPanel(into: currentFolder) })
        )
    }

    private var emptySymbol: String {
        switch model.sidebarSelection {
        case .pinned: "pin"
        case .recents: "clock"
        case .locked: "lock"
        default: "tray"
        }
    }

    private var emptyTitle: String {
        switch model.sidebarSelection {
        case .pinned: "Nothing pinned yet"
        case .recents: "Nothing used yet"
        case .locked: "No sensitive items"
        default: model.mainSearch.isEmpty ? "This folder is empty" : "No matches"
        }
    }

    private var emptyMessage: String {
        switch model.sidebarSelection {
        case .pinned: "Pin the handful of things you reach for daily and they’ll be first in the panel, before you type anything."
        case .recents: "Once you start summoning items, the ones you use most will collect here."
        case .locked: "Mark an item or a folder as sensitive to encrypt it behind your PIN and Touch ID."
        default: "Drop files here, paste from the clipboard tray, or press \(model.settings.quickSaveHotKey.displayString) anywhere to save what’s selected."
        }
    }
}

struct ItemRow: View {
    @Bindable var model: AppModel
    let item: ItemSnapshot
    let canReorder: Bool
    let onSelect: (UUID) -> Void

    /// The row height `LibraryRow` draws, which the drop delegate needs in order to
    /// turn a pointer position into "above" or "below".
    static let height: CGFloat = 40

    private var dropEdge: VerticalAlignment? {
        guard let target = model.itemDropTarget, target.itemID == item.id else { return nil }
        return target.placeAfter ? .bottom : .top
    }

    var body: some View {
        // The same 40pt row the panel and the menu bar draw. Three surfaces had
        // grown three heights and three type scales; now there is one component.
        LibraryRow(item: item,
                   isSelected: model.mainSelection == item.id,
                   onCopy: { model.use(item.id, style: .copy) })
            .contentShape(.rect)
            // Double-click copies. Registered before the single tap so the single
            // click still only selects.
            // The single tap is the primary gesture so selection is immediate. A
            // plain `.onTapGesture(count: 2)` ahead of it makes SwiftUI hold every
            // single click until the double-click interval expires — which is what
            // made selecting feel laggy, not any work being done.
            .onTapGesture { onSelect(item.id) }
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                onSelect(item.id)
                model.use(item.id, style: .copy)
            })
            .overlay(alignment: .top) { if dropEdge == .top { DropLine() } }
            .overlay(alignment: .bottom) { if dropEdge == .bottom { DropLine() } }
            .contextMenu { ItemContextMenu(model: model, item: item) }
            .onDrag { model.dragProvider(for: item.id) ?? model.identityOnlyDragProvider(for: item.id) }
            .modifier(ReorderDropTarget(model: model, item: item, enabled: canReorder))
    }
}

/// Applied conditionally, because a drop target that accepts a drag it cannot honour
/// is worse than none: it shows an insertion line and then does nothing.
private struct ReorderDropTarget: ViewModifier {
    let model: AppModel
    let item: ItemSnapshot
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [SummonDragType.item],
                           delegate: ItemReorderDropDelegate(item: item, model: model,
                                                             rowHeight: ItemRow.height))
        } else {
            content
        }
    }
}

struct ItemCard: View {
    @Bindable var model: AppModel
    let item: ItemSnapshot
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Theme.color(for: item.kind).opacity(0.10))
                if !item.isLocked, let url = model.thumbnailURL(for: item.id),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(.rect(cornerRadius: Theme.Radius.small, style: .continuous))
                } else if item.kind.isTextual && !item.isLocked {
                    Text(item.previewLine)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(5)
                        .padding(Theme.Space.xs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    KindBadge(kind: item.kind, size: 34, isLocked: item.isLocked)
                }
            }
            .frame(height: 96)
            .clipped()

            HStack(spacing: Theme.Space.xxs) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 8))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(Theme.Space.xs)
        .background(isSelected ? Theme.selection : Theme.surface,
                    in: .rect(cornerRadius: Theme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .strokeBorder(isSelected ? Theme.primaryText.opacity(0.6) : Theme.hairline, lineWidth: 1)
        )
        .contextMenu { ItemContextMenu(model: model, item: item) }
        .onDrag { model.dragProvider(for: item.id) ?? model.identityOnlyDragProvider(for: item.id) }
    }
}

struct ItemContextMenu: View {
    @Bindable var model: AppModel
    let item: ItemSnapshot

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { model.use(item.id, style: .copy) }
        Button(item.isPinned ? "Unpin" : "Pin",
               systemImage: item.isPinned ? "pin.slash" : "pin") { model.togglePin(item.id) }
        FolderPickerMenu(model: model, item: item)
        if item.kind.isBlobBacked {
            Button("Open", systemImage: "arrow.up.forward.app") { model.use(item.id, style: .open) }
            Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder(item.id) }
        }
        Divider()
        Button(item.isSensitive ? "Remove Sensitivity" : "Mark as Sensitive",
               systemImage: item.isSensitive ? "lock.open" : "lock") {
            model.setItemSensitive(item.id, !item.isSensitive)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { model.deleteItem(item.id) }
    }
}

struct ClipboardListView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.clipboard.entries.isEmpty {
                EmptyStateView(
                    symbol: "doc.on.clipboard",
                    title: "Clipboard is quiet",
                    message: model.settings.clipboardHistoryEnabled
                        ? "Anything you copy shows up here, ready to keep with one click. Password manager copies are never recorded."
                        : "Clipboard history is turned off. Turn it on in Settings to capture what you copy."
                )
            } else {
                List {
                    ForEach(model.clipboard.entries) { entry in
                        HStack(spacing: Theme.Space.s) {
                            KindBadge(kind: entry.kind, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.preview)
                                    .font(.system(size: 12))
                                    .lineLimit(2)
                                Text("\(entry.sourceAppName ?? "Unknown") · \(entry.capturedAt.formatted(.relative(presentation: .numeric)))")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            Spacer()
                            Button("Keep") { model.saveClipboardEntry(entry) }
                                .buttonStyle(.borderless)
                                .tint(Theme.primaryText)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Keep in Library") { model.saveClipboardEntry(entry) }
                            Button("Remove", role: .destructive) { model.clipboard.remove(entry.id) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}
