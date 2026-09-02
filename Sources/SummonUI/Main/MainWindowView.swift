import AppKit
import SwiftUI
import SummonKit

/// The library window: organise here, summon everywhere else.
public struct MainWindowView: View {
    @Bindable var model: AppModel

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
                Button("New Snippet", systemImage: "text.alignleft") { model.beginNewSnippet() }
                    .keyboardShortcut("n")
                Button("New Folder", systemImage: "folder.badge.plus") { model.beginNewFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
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

}
