// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// Folders and tags, managed rather than merely browsed.
///
/// On the Mac these live in the sidebar and are changed by dragging, right-clicking
/// and renaming in place. A phone has none of those, and the chips on the home screen
/// are deliberately a filter and nothing more — so the managing happens here, where a
/// row can be swiped, a name typed, and a folder moved by picking its parent.
struct FolderManagerView: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void

    @State private var renaming: SummonFolder?
    @State private var draftName = ""
    @State private var creatingIn: SummonFolder??
    @State private var iconTarget: SummonFolder?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(flattened, id: \.folder.id) { entry in
                        row(entry.folder, depth: entry.depth)
                    }
                } header: {
                    Text("Folders")
                } footer: {
                    Text("Deleting a folder keeps the items in it; they move back to All Items.")
                }

                Section("Tags") {
                    let tags = model.store.tagsInUse()
                    if tags.isEmpty {
                        Text("No tags yet")
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    ForEach(tags, id: \.id) { tag in
                        HStack {
                            Text("#\(tag.name)")
                            Spacer()
                            Text("\((tag.items ?? []).count)")
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .swipeActions {
                            Button(role: .destructive) { model.deleteTag(tag) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                draftName = tag.name
                                renamingTag = tag
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Theme.accent)
                        }
                    }
                }
            }
            .navigationTitle("Organise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creatingIn = .some(nil)
                        draftName = ""
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
            }
            .alert("Rename folder", isPresented: Binding(get: { renaming != nil },
                                                         set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $draftName)
                Button("Rename") {
                    if let folder = renaming, !draftName.isEmpty {
                        model.store.renameFolder(folder, to: draftName)
                        model.store.refresh()
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert("Rename tag", isPresented: Binding(get: { renamingTag != nil },
                                                      set: { if !$0 { renamingTag = nil } })) {
                TextField("Name", text: $draftName)
                Button("Rename") {
                    if let tag = renamingTag, !draftName.isEmpty { model.renameTag(tag, to: draftName) }
                    renamingTag = nil
                }
                Button("Cancel", role: .cancel) { renamingTag = nil }
            }
            .alert("New folder", isPresented: Binding(get: { creatingIn != nil },
                                                      set: { if !$0 { creatingIn = nil } })) {
                TextField("Name", text: $draftName)
                Button("Create") {
                    if let parent = creatingIn, !draftName.isEmpty {
                        _ = model.store.createFolder(name: draftName, parent: parent)
                        model.store.refresh()
                    }
                    creatingIn = nil
                }
                Button("Cancel", role: .cancel) { creatingIn = nil }
            }
            .sheet(item: $iconTarget) { folder in
                FolderIconSheet(model: model, folder: folder) { iconTarget = nil }
            }
        }
    }

    @State private var renamingTag: SummonTag?

    private struct Entry { let folder: SummonFolder; let depth: Int }

    /// The tree, flattened into rows that carry their own indentation.
    ///
    /// Nesting by indentation rather than disclosure arrows: these trees are three or
    /// four deep at most, and a phone should show the shape rather than make you go
    /// looking for it. Flattened rather than drawn recursively because a SwiftUI view
    /// that contains itself has no finite type.
    private var flattened: [Entry] {
        func walk(_ folders: [SummonFolder], depth: Int) -> [Entry] {
            folders.flatMap { folder in
                [Entry(folder: folder, depth: depth)]
                    + walk(model.store.children(of: folder), depth: depth + 1)
            }
        }
        return walk(model.store.rootFolders(), depth: 0)
    }

    private func row(_ folder: SummonFolder, depth: Int) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: folder.symbolName.isEmpty ? "folder" : folder.symbolName)
                .foregroundStyle(Theme.folderColor(folder.colorName))
                .frame(width: 24)
            Text(folder.name)
            if folder.isSensitive {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.accent)
            }
            Spacer()
            Text("\(folder.items?.count ?? 0)")
                .foregroundStyle(Theme.tertiaryText)
                .font(Theme.Typography.meta)
        }
        .padding(.leading, CGFloat(depth) * 16)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.store.deleteFolder(folder)
                model.store.refresh()
                model.runSearch()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                draftName = folder.name
                renaming = folder
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            Button("New Folder Inside", systemImage: "folder.badge.plus") {
                draftName = ""
                creatingIn = .some(folder)
            }
            Button("Change Icon", systemImage: "paintpalette") { iconTarget = folder }
            Button(folder.isSensitive ? "Remove Sensitivity" : "Mark as Sensitive",
                   systemImage: folder.isSensitive ? "lock.open" : "lock") {
                model.setFolderSensitive(folder, !folder.isSensitive)
            }
        }
    }
}

/// The icon and colour picker, which already exists — it just had nowhere to be
/// presented from on a phone.
private struct FolderIconSheet: View {
    @Bindable var model: AppModel
    let folder: SummonFolder
    let dismiss: () -> Void
    @State private var presented = true

    var body: some View {
        NavigationStack {
            FolderIconPicker(model: model, folder: folder, isPresented: $presented)
                .padding()
                .navigationTitle(folder.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: presented) { _, open in if !open { dismiss() } }
    }
}
#endif
