import AppKit
import SwiftUI
import SummonKit

public struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingFolder: UUID?
    @State private var renameText = ""

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
                     count: Int, tint: Color = Theme.accent) -> some View {
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
                        .foregroundStyle(model.vault.isUnlocked ? Theme.success : Theme.spark)
                    Text(model.vault.isUnlocked ? "Sensitive items unlocked" : "Sensitive items locked")
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.xs)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A folder and everything under it. Recursive, with drop targets on every node.
struct FolderRow: View {
    @Bindable var model: AppModel
    let folder: SummonFolder
    let depth: Int
    @Binding var renamingFolder: UUID?
    @Binding var renameText: String
    @State private var isExpanded = true
    @State private var isTargeted = false

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
                        .foregroundStyle(Theme.spark)
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
        .background(isTargeted ? Theme.accentWash : .clear)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await FolderRow.urls(from: providers)
                guard !urls.isEmpty else { return }
                model.importDroppedFiles(urls, into: folder)
            }
            return true
        }
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
