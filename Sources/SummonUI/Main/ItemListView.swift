import AppKit
import SwiftUI
import SummonKit

/// The middle column: everything in the current sidebar selection, as a dense list
/// or a grid when the content is visual.
public struct ItemListView: View {
    @Bindable var model: AppModel
    let items: [ItemSnapshot]
    @State private var gridColumns = 1

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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await FolderRow.urls(from: providers)
                guard !urls.isEmpty else { return }
                model.importDroppedFiles(urls, into: currentFolder)
            }
            return true
        }
    }

    private var currentFolder: SummonFolder? {
        guard case .folder(let id) = model.sidebarSelection else { return nil }
        return model.store.allFolders().first { $0.id == id }
    }

    private var list: some View {
        List(selection: $model.mainSelection) {
            ForEach(items) { item in
                ItemRow(model: model, item: item)
                    .tag(item.id)
            }
        }
        .listStyle(.inset)
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

    var body: some View {
        // The same 40pt row the panel and the menu bar draw. Three surfaces had
        // grown three heights and three type scales; now there is one component.
        LibraryRow(item: item, isSelected: model.mainSelection == item.id)
            .contextMenu { ItemContextMenu(model: model, item: item) }
            // .onDrag swallows the click that a List uses to select, so items in the
            // library were never clickable — and because clicking is how the list
            // takes focus, arrow keys never worked there either. A simultaneous
            // gesture sets the selection without taking the drag away.
            .simultaneousGesture(TapGesture().onEnded { model.mainSelection = item.id })
            .onDrag { model.dragProvider(for: item.id) ?? NSItemProvider() }
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
        .onDrag { model.dragProvider(for: item.id) ?? NSItemProvider() }
    }
}

struct ItemContextMenu: View {
    @Bindable var model: AppModel
    let item: ItemSnapshot

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { model.use(item.id, style: .copy) }
        Button(item.isPinned ? "Unpin" : "Pin",
               systemImage: item.isPinned ? "pin.slash" : "pin") { model.togglePin(item.id) }
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
