import AppKit
import SwiftUI
import SummonKit

/// The library window: organise here, summon everywhere else.
public struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var newFolderName = ""
    @State private var showingNewSnippet = false
    @State private var newSnippetTitle = ""
    @State private var newSnippetBody = ""

    public init(model: AppModel) { self.model = model }

    private var items: [ItemSnapshot] { model.itemsForSidebar() }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 196, ideal: 224, max: 280)
        } content: {
            ItemListView(model: model, items: items)
                .frame(minWidth: 300)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 560)
                .navigationTitle(model.sidebarTitle)
                .navigationSubtitle(subtitle)
                .searchable(text: $model.mainSearch, placement: .toolbar, prompt: "Search this view")
        } detail: {
            if let id = model.mainSelection, items.contains(where: { $0.id == id }) {
                ItemDetailView(model: model, itemID: id)
            } else {
                detailPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, Theme.Space.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.panelIn, value: model.toast)
        .alert("New Folder", isPresented: $model.pendingNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.isEmpty ? "New Folder" : newFolderName
                let parent: SummonFolder? = {
                    guard case .folder(let id) = model.sidebarSelection else { return nil }
                    return model.store.allFolders().first { $0.id == id }
                }()
                let folder = model.store.createFolder(name: name, parent: parent)
                model.sidebarSelection = .folder(folder.id)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .sheet(isPresented: $model.pendingNewSnippet) { newSnippetSheet }
        .alert("Delete “\(model.pendingDeleteTitle)”?",
               isPresented: Binding(get: { model.pendingDeleteID != nil },
                                    set: { if !$0 { model.pendingDeleteID = nil } })) {
            Button("Delete", role: .destructive) { model.confirmPendingDelete() }
            Button("Cancel", role: .cancel) { model.pendingDeleteID = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var subtitle: String {
        let count = items.count
        if case .clipboard = model.sidebarSelection {
            return "\(model.clipboard.entries.count) recent"
        }
        return count == 1 ? "1 item" : "\(count) items"
    }

    private var detailPlaceholder: some View {
        EmptyStateView(
            symbol: "sparkles",
            title: "Select something",
            message: "Choose an item to edit it here. To actually use one, press \(model.settings.summonHotKey.displayString) from wherever you’re working — that’s the fast path."
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("New Snippet", systemImage: "text.alignleft") { model.pendingNewSnippet = true }
                Button("New Folder", systemImage: "folder.badge.plus") { model.pendingNewFolder = true }
                Divider()
                Button("Import Files…", systemImage: "square.and.arrow.down") {
                    model.presentImportPanel(into: currentFolder)
                }
                if model.clipboard.entries.first != nil {
                    Button("Save Clipboard", systemImage: "doc.on.clipboard") {
                        model.saveCurrentClipboard()
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("Layout", selection: $model.useGridLayout) {
                Image(systemName: "list.bullet").tag(false)
                    .accessibilityLabel("List view")
                Image(systemName: "square.grid.2x2").tag(true)
                    .accessibilityLabel("Grid view")
            }
            .pickerStyle(.segmented)
            .help("Switch between list and grid")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.summon()
            } label: {
                Label("Summon", systemImage: "sparkle.magnifyingglass")
            }
            .help("Open the summon panel (\(model.settings.summonHotKey.displayString))")
        }
    }

    private var currentFolder: SummonFolder? {
        guard case .folder(let id) = model.sidebarSelection else { return nil }
        return model.store.allFolders().first { $0.id == id }
    }

    private var newSnippetSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("New Snippet")
                .font(.system(size: 15, weight: .semibold))
            TextField("Title", text: $newSnippetTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $newSnippetBody)
                .font(.system(size: 12.5))
                .frame(minHeight: 220)
                .cardBackground(raised: true)
            Text("Tip: {{first_name}} becomes a fill-in field. {{date:+3d}} inserts a date three days out.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)

            HStack {
                Spacer()
                Button("Cancel") { resetNewSnippet() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task {
                        _ = await model.importer.importText(
                            newSnippetBody,
                            title: newSnippetTitle.isEmpty ? nil : newSnippetTitle,
                            into: currentFolder
                        )
                        model.runSearch()
                        resetNewSnippet()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryText)
                .keyboardShortcut(.defaultAction)
                .disabled(newSnippetBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.m)
        .frame(width: 520)
    }

    private func resetNewSnippet() {
        newSnippetTitle = ""
        newSnippetBody = ""
        model.pendingNewSnippet = false
    }
}
