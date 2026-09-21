// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// The iPad: the phone's home with the folders pulled back out into a sidebar.
///
/// It ran the Mac's `MainWindowView` before, which is a window built around hover,
/// right-click and a 32pt row — usable with a trackpad, awkward with a thumb. This is
/// the same three columns, sized for touch and sharing every screen with the phone, so
/// there is one iOS app rather than two.
public struct PadRootView: View {
    @Bindable var model: AppModel
    // The list is always on screen; the sidebar is a toggle away.
    //
    // `.all` made the sidebar an overlay in portrait, covering the list it is meant to
    // filter. `.automatic` went the other way and opened on the empty detail pane,
    // which is a blank screen saying "nothing selected" before you have had a chance
    // to select anything. Two columns is the one that is right in both orientations.
    @State private var columns = NavigationSplitViewVisibility.doubleColumn
    @State private var detail: UUID?
    @State private var showingSettings = false
    @State private var showingVault = false
    @State private var organising = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool

    public init(model: AppModel) { self.model = model }

    private var sections: PhoneSections { PhoneSections(model: model) }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } content: {
            list
                // Wide enough for a title and its preview line. The default content
                // column truncated both, which is the one thing a list of titles
                // cannot afford to do.
                .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 520)
        } detail: {
            if let detail {
                PhoneItemDetailView(model: model, itemID: detail)
            } else {
                ContentUnavailableView("Nothing selected", systemImage: "sparkles",
                                       description: Text("Choose an item to read it."))
                    .background(GlassBackground(material: .underWindowBackground, bloom: 0.3))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .sheet(isPresented: $showingSettings) {
            PhoneSettingsView(model: model) { showingSettings = false }
        }
        .sheet(isPresented: $showingVault) {
            VaultSheet(model: model) { showingVault = false }
        }
        .sheet(isPresented: $organising) {
            FolderManagerView(model: model) { organising = false }
        }
        .phoneSheets(model: model)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, Theme.Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.panelIn, value: model.toast)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, model.vault.isUnlocked { model.lockVaultNow() }
        }
    }

    /// Folders and tags as a list rather than as chips: an iPad has the width for the
    /// shape of the tree, which is the one thing the phone's chip bar cannot show.
    private var sidebar: some View {
        List(selection: Binding(get: { model.sidebarSelection },
                                set: { model.sidebarSelection = $0 ?? .all; model.runSearch() })) {
            Section {
                Label("All Items", systemImage: "square.grid.2x2").tag(SidebarSelection.all)
                Label("Pinned", systemImage: "pin").tag(SidebarSelection.pinned)
                Label("Recents", systemImage: "clock").tag(SidebarSelection.recents)
                if model.store.snapshots.contains(where: \.isSensitive) {
                    Label("Sensitive", systemImage: "lock").tag(SidebarSelection.locked)
                }
            }

            Section("Folders") {
                ForEach(model.store.rootFolders(), id: \.id) { folder in
                    Label(folder.name,
                          systemImage: folder.symbolName.isEmpty ? "folder" : folder.symbolName)
                        .tag(SidebarSelection.folder(folder.id))
                }
            }

            if !model.store.tagsInUse().isEmpty {
                Section("Tags") {
                    ForEach(model.store.tagsInUse(), id: \.id) { tag in
                        Label("#\(tag.name)", systemImage: "number")
                            .tag(SidebarSelection.tag(tag.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Summon")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { organising = true } label: {
                    Label("Organise", systemImage: "folder.badge.gearshape")
                }
            }
        }
    }

    private var list: some View {
        Group {
            if sections.isEmpty {
                PhoneEmptyState(model: model, isSearching: sections.isSearching)
            } else {
                List(selection: $detail) {
                    ForEach(sections.sections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                PhoneItemRow(item: item,
                                             onCopy: {
                                                 model.use(item.id, style: .copy)
                                                 if !item.isLocked { Theme.Haptics.success() }
                                             },
                                             onOpen: { detail = item.id })
                                .tag(item.id)
                                .listRowBackground(Color.clear)
                                .contextMenu {
                                    PhoneItemMenu(model: model, item: item) { detail = item.id }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(GlassBackground(material: .underWindowBackground, bloom: 0.35))
        .navigationTitle(model.sidebarTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.mainSearch, prompt: "Search your library")
        .searchFocused($searchFocused)
        .onChange(of: model.mainSearch) { _, _ in model.runSearch() }
        // An iPad with a keyboard attached is a Mac-shaped thing, and the Mac's
        // shortcuts are already a tested map. These four are the ones that make sense
        // without a panel to route the rest through.
        .background {
            Group {
                Button("Search") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("New Snippet") { model.beginNewSnippet() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Settings") { showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Organise") { organising = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            .hidden()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            if model.vault.isConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingVault = true } label: {
                        Label("Sensitive items",
                              systemImage: model.vault.isUnlocked ? "lock.open" : "lock")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                AddMenu(model: model) { organising = true }
            }
        }
    }
}
#endif
