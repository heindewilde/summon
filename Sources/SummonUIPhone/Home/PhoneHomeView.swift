// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import CoreSpotlight
import SummonKit
import SummonUI
import SwiftUI

/// The phone's home: search at the top, what you reach for underneath.
///
/// The Mac's window is sidebar → list → item, which is right for a window that shows
/// all three at once and wrong for a screen that shows one: on a phone it was three
/// taps to reach anything, and the first two were furniture. Summon is for finding one
/// thing quickly, so the phone opens on the finding.
public struct PhoneHomeView: View {
    @Bindable var model: AppModel
    @State private var showingSettings = false
    @State private var showingVault = false
    @State private var detail: UUID?
    @State private var organising = false
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel) { self.model = model }

    #if DEBUG
    /// Opens one screen straight away, so the App Store screenshots can be captured
    /// without a human tapping through five of them in the right order. Debug only:
    /// a shipping build has no way to reach it, and the Mac's `SnapshotRunner` is the
    /// same idea for the same reason.
    ///
    ///     xcrun simctl launch <device> com.heindewilde.summon -SUMMON_SCREEN detail
    private var requestedScreen: String? {
        ProcessInfo.processInfo.arguments.firstIndex(of: "-SUMMON_SCREEN").flatMap {
            let next = $0 + 1
            return next < ProcessInfo.processInfo.arguments.count
                ? ProcessInfo.processInfo.arguments[next] : nil
        }
    }

    private func openRequestedScreen() {
        switch requestedScreen {
        case "detail": detail = model.store.snapshots.first(where: { !$0.isLocked })?.id
        case "fill":
            if let id = model.store.snapshots.first(where: \.hasPlaceholders)?.id {
                model.use(id, style: .copy)
            }
        case "settings": showingSettings = true
        case "organise": organising = true
        case "vault": showingVault = true
        default: break
        }
    }
    #endif

    private var sections: PhoneSections { PhoneSections(model: model) }

    public var body: some View {
        NavigationStack {
            Group {
                if sections.isEmpty {
                    PhoneEmptyState(model: model, isSearching: sections.isSearching)
                } else {
                    list
                }
            }
            .background(GlassBackground(material: .underWindowBackground, bloom: 0.35))
            .navigationTitle("Summon")
            .searchable(text: $model.mainSearch, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search your library")
            .onChange(of: model.mainSearch) { _, _ in model.runSearch() }
            .toolbar { toolbar }
            .navigationDestination(item: $detail) { id in
                PhoneItemDetailView(model: model, itemID: id)
            }
            // A Spotlight result has to land on the item it named. Indexing without
            // this is a search that finds your things and then shows you a list of
            // everything, which is worse than not appearing in Spotlight at all.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let id = UUID(uuidString: identifier),
                      model.store.snapshots.contains(where: { $0.id == id })
                else { return }
                model.mainSearch = ""
                model.sidebarSelection = .all
                model.runSearch()
                detail = id
            }
        }
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
        // A phone is handed to other people in a way a Mac is not, so sensitive items
        // lock the moment Summon is no longer what is on screen — ahead of the
        // auto-lock timer, which then only governs how long an *open* app stays
        // unlocked.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, model.vault.isUnlocked { model.lockVaultNow() }
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
        #if DEBUG
        .task { openRequestedScreen() }
        #endif
    }

    private var list: some View {
        List {
            // The chips ride with the content rather than pinned above it: a
            // `safeAreaInset` above the list swallowed the large title, and a phone
            // has no room to spend on furniture that never scrolls away.
            Section {
                FilterChipBar(model: model)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(sections.sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        PhoneItemRow(item: item,
                                     onCopy: { copy(item) },
                                     onOpen: { detail = item.id })
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                model.togglePin(item.id)
                                Theme.Haptics.selection()
                            } label: {
                                Label(item.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                            }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                model.requestDelete(item.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                detail = item.id
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                            }
                            .tint(Theme.secondaryText)
                        }
                        .contextMenu {
                            PhoneItemMenu(model: model, item: item) { detail = item.id }
                        }
                    }
                    // Only inside a folder, and only when nothing is typed — see
                    // `PhoneSections.canReorder`.
                    .onMove { offsets, destination in
                        guard sections.canReorder else { return }
                        sections.move(section.items, from: offsets, to: destination)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        // Only where there is an order to change; an Edit button over a ranked list
        // offers a drag that cannot be honoured.
        if sections.canReorder {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
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

    /// The summon moment, on a phone: the clipboard is the destination, because no app
    /// may type into another. A haptic as well as a toast — the result of this action
    /// is invisible until you paste it somewhere else.
    private func copy(_ item: ItemSnapshot) {
        model.use(item.id, style: .copy)
        if !item.isLocked, !item.hasPlaceholders { Theme.Haptics.success() }
    }
}
#endif
