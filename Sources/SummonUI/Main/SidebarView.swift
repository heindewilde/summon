import AppKit
import SwiftUI
import SummonKit

public struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingFolder: UUID?
    @State private var renameText = ""
    @State private var rootTargeted = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        List(selection: Binding(
            get: { model.sidebarSelection },
            set: { if let new = $0 { model.sidebarSelection = new } }
        )) {
            Section("Library") {
                row(.all, "All Items", "square.grid.2x2", count: model.store.snapshots.count)
                row(.recents, "Recents", "clock",
                    count: model.store.snapshots.count { $0.lastUsedAt != nil })
                row(.pinned, "Pinned", "pin", count: model.store.snapshots.count(where: \.isPinned))
                if model.vault.isConfigured {
                    row(.locked, "Sensitive", "lock",
                        count: model.store.snapshots.count(where: \.isSensitive))
                }
                row(.clipboard, "Clipboard", "doc.on.clipboard", count: model.clipboard.entries.count)
            }

            Section("Folders") {
                ForEach(model.store.rootFolders(), id: \.id) { folder in
                    FolderRow(model: model, folder: folder, depth: 0,
                              renamingFolder: $renamingFolder, renameText: $renameText)
                }
                Button {
                    model.beginNewFolder()
                } label: {
                    Label("New Folder", systemImage: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                // Doubles as the top-level drop target: without somewhere to drop
                // *outside* every folder, a nested folder could be nested further but
                // never dragged back out.
                .background(rootTargeted ? Theme.selection : .clear)
                .onDrop(of: [.text],
                        delegate: RootFolderDropDelegate(model: model, isTargeted: $rootTargeted))
            }

            let tags = model.store.tagsInUse()
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.id) { tag in
                        row(.tag(tag.name), "#\(tag.name)", "number",
                            count: (tag.items ?? []).count)
                    }
                }
            }

            Section("Types") {
                ForEach(ItemKind.allCases.filter { $0 != .richText }, id: \.self) { kind in
                    let count = model.store.snapshots.count {
                        kind == .text ? $0.kind.isTextual : $0.kind == kind
                    }
                    if count > 0 {
                        row(.kind(kind), kind.pluralName, kind.symbolName, count: count,
                            tint: Theme.color(for: kind))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { vaultFooter }
    }

    private func row(_ selection: SidebarSelection, _ title: String, _ symbol: String,
                     count: Int, tint: Color = Theme.primaryText) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .tag(selection)
    }

    @ViewBuilder
    private var vaultFooter: some View {
        if model.vault.isConfigured {
            Divider().overlay(Theme.hairline)
            Button {
                model.toggleLock()
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: model.vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(model.vault.isUnlocked ? Theme.success : Theme.secondaryText)
                    Text(model.vault.isUnlocked ? "Sensitive items unlocked" : "Sensitive items locked")
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(.bar)
        }
    }
}

/// A folder and everything under it. Recursive, with drop targets on every node.
/// A folder row's insertion indicator.
private var dropLine: some View {
    Rectangle()
        .fill(Theme.primaryText)
        .frame(height: 2)
        .padding(.horizontal, Theme.Space.xs)
}

struct FolderRow: View {
    @Bindable var model: AppModel
    let folder: SummonFolder
    let depth: Int
    @Binding var renamingFolder: UUID?
    @Binding var renameText: String
    @State private var isExpanded = true
    @State private var isTargeted = false
    @State private var dropZone: FolderDropZone?

    var body: some View {
        Group {
            if folder.sortedChildren.isEmpty {
                label
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(folder.sortedChildren, id: \.id) { child in
                        FolderRow(model: model, folder: child, depth: depth + 1,
                                  renamingFolder: $renamingFolder, renameText: $renameText)
                    }
                } label: {
                    label
                }
            }
        }
    }

    private var label: some View {
        Label {
            HStack {
                if renamingFolder == folder.id {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            model.store.renameFolder(folder, to: renameText)
                            renamingFolder = nil
                        }
                } else {
                    Text(folder.name)
                }
                Spacer()
                if folder.isEffectivelySensitive {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryText)
                }
                let count = folder.allItems().count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: folder.symbolName)
                .foregroundStyle(Theme.folderColor(folder.colorName))
        }
        .tag(SidebarSelection.folder(folder.id))
        // Highlights differently depending on what the drop would do: a fill means
        // "inside this folder", a line means "beside it".
        .background(dropZone == .into ? Theme.selection : .clear)
        .overlay(alignment: .top) {
            if dropZone == .before { dropLine }
        }
        .overlay(alignment: .bottom) {
            if dropZone == .after { dropLine }
        }
        .onDrag {
            // Prefixed so a folder drag is distinguishable from arbitrary text
            // dropped in from another app.
            NSItemProvider(object: (FolderDragPrefix + folder.id.uuidString) as NSString)
        }
        .onDrop(of: [.text, .fileURL],
                delegate: FolderDropDelegate(folder: folder, model: model, zone: $dropZone))
        .contextMenu {
            Button("Rename") {
                renameText = folder.name
                renamingFolder = folder.id
            }
            Button("New Folder Inside") {
                _ = model.store.createFolder(name: "New Folder", parent: folder)
            }
            Button("Add Files…") { model.presentImportPanel(into: folder) }
            Divider()
            Button(folder.isSensitive ? "Remove Sensitivity" : "Mark as Sensitive") {
                model.setFolderSensitive(folder, !folder.isSensitive)
            }
            Divider()
            Button("Delete Folder", role: .destructive) {
                model.store.deleteFolder(folder)
                model.runSearch()
            }
        }
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let data = try? await provider.loadItem(forTypeIdentifier: "public.file-url") as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            }
        }
        return urls
    }
}
