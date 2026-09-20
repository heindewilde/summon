// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
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

    public init(model: AppModel) { self.model = model }

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
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showingSettings) {
            PhoneSettingsView(model: model) { showingSettings = false }
        }
        .sheet(isPresented: $showingVault) {
            VaultSheet(model: model) { showingVault = false }
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
        if model.vault.isConfigured {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingVault = true } label: {
                    Label("Sensitive items",
                          systemImage: model.vault.isUnlocked ? "lock.open" : "lock")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            AddMenu(model: model)
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
