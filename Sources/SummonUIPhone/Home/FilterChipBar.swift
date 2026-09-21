// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// The sidebar, flattened into a row of chips.
///
/// The Mac keeps folders, tags and kinds in a column that is always on screen. A phone
/// has no column to spare, and a hierarchy behind a button is a hierarchy nobody
/// opens — so the same choices become one scrolling row above the list, with the
/// current one lit.
///
/// It writes to `model.sidebarSelection`, which is what `itemsForSidebar()` already
/// reads, rather than inventing a second idea of what is being shown.
struct FilterChipBar: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                chip("All", systemImage: "square.grid.2x2", selection: .all)

                if model.store.snapshots.contains(where: \.isSensitive) {
                    chip("Sensitive", systemImage: "lock", selection: .locked)
                }

                ForEach(model.store.rootFolders(), id: \.id) { folder in
                    chip(folder.name, systemImage: folder.symbolName.isEmpty ? "folder" : folder.symbolName,
                         selection: .folder(folder.id), tint: Theme.folderColor(folder.colorName))
                }

                ForEach(model.store.tagsInUse(), id: \.id) { tag in
                    chip("#\(tag.name)", systemImage: nil, selection: .tag(tag.name))
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.xs)
        }
        .scrollIndicators(.hidden)
        // The chips scroll under the search field; clipping keeps them from appearing
        // to slide out of the screen's rounded corner.
        .scrollClipDisabled(false)
    }

    @ViewBuilder
    private func chip(_ label: String, systemImage: String?, selection: SidebarSelection,
                      tint: Color? = nil) -> some View {
        let isOn = model.sidebarSelection == selection
        Button {
            Theme.Haptics.selection()
            // Tapping the current chip clears it, so there is always a way back to
            // everything without hunting for the "All" chip at the far left.
            model.sidebarSelection = isOn ? .all : selection
            model.runSearch()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(isOn ? Theme.onAccent : (tint ?? Theme.secondaryText))
                }
                Text(label)
                    .font(Theme.Typography.meta.weight(.medium))
                    .foregroundStyle(isOn ? Theme.onAccent : Theme.secondaryText)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(isOn ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}
#endif
