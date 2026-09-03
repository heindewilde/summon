import AppKit
import SwiftUI
import SummonKit

/// The always-there surface: pinned and recent items, the clipboard tray, and the
/// things you would otherwise have to open a window to do.
public struct MenuBarView: View {
    @Bindable var model: AppModel
    public var openMainWindow: () -> Void
    public var openSettings: () -> Void

    public init(model: AppModel, openMainWindow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
        self.openSettings = openSettings
    }

    private var pinned: [ItemSnapshot] {
        Array(model.store.snapshots.filter(\.isPinned).prefix(5))
    }

    private var recents: [ItemSnapshot] {
        Array(model.store.snapshots
            .filter { $0.lastUsedAt != nil && !$0.isPinned }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(5))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.hairline)

            SnapshotSafeScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if pinned.isEmpty && recents.isEmpty && model.clipboard.entries.isEmpty {
                        emptyHint
                    }
                    if !pinned.isEmpty {
                        section("Pinned", items: pinned)
                    }
                    if !recents.isEmpty {
                        section("Recent", items: recents)
                    }
                    if !model.clipboard.entries.isEmpty {
                        clipboardSection
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
            // Sized to what it holds, capped so a long library still scrolls. Fixed
            // at 380 it showed three items above a void.
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.hairline)
            footer
        }
        .frame(width: 330)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.primaryText)
            Text("Summon")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if model.vault.isConfigured {
                Button {
                    model.toggleLock()
                } label: {
                    Image(systemName: model.vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(model.vault.isUnlocked ? Theme.success : Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help(model.vault.isUnlocked ? "Lock sensitive items" : "Unlock sensitive items")
            }

            Text(model.settings.summonHotKey.displayString)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.hairline, in: .rect(cornerRadius: 4))
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs + 1)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("Nothing saved yet")
                .font(.system(size: 12, weight: .medium))
            Text("Copy something and press \(model.settings.quickSaveHotKey.displayString), or open Summon and drop files in.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs)
    }

    // MARK: - Sections

    private func section(_ title: String, items: [ItemSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionHeader(title)
            ForEach(items) { item in
                MenuBarRow(item: item) {
                    model.focus.capture()
                    model.use(item.id, style: .paste)
                }
            }
        }
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                sectionHeader("Clipboard")
                Spacer()
                Button("Clear") { model.clipboard.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.trailing, Theme.Space.s)
            }
            ForEach(model.clipboard.entries.prefix(4)) { entry in
                ClipboardRow(entry: entry) {
                    model.saveClipboardEntry(entry)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.tertiaryText)
            .padding(.horizontal, Theme.Space.s)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, 1)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            MenuAction(title: "Open Summon", symbol: "sparkle.magnifyingglass",
                       shortcut: model.settings.summonHotKey.displayString) {
                model.summon()
            }
            MenuAction(title: "Save Clipboard", symbol: "square.and.arrow.down") {
                model.saveCurrentClipboard()
            }
            MenuAction(title: "Library…", symbol: "square.grid.2x2", action: openMainWindow)
            MenuAction(title: "Settings…", symbol: "gearshape", shortcut: "⌘,", action: openSettings)
            Divider().overlay(Theme.hairline).padding(.vertical, 2)
            MenuAction(title: "Quit Summon", symbol: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
    }
}

struct MenuBarRow: View {
    let item: ItemSnapshot
    let action: () -> Void
    var body: some View {
        // This used to hand hover in as selection. `LibraryRow` takes a `RowState` now,
        // so the row is simply left at its default and resolves its own hover — the
        // mistake is no longer expressible.
        Button(action: action) {
            LibraryRow(item: item)
        }
        .buttonStyle(.plain)
    }
}

struct ClipboardRow: View {
    let entry: ClipboardMonitor.Entry
    let save: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            KindBadge(kind: entry.kind, size: 20)
            Text(entry.preview)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Space.xxs)
            if hovering {
                Button(action: save) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.primaryText)
                }
                .buttonStyle(.plain)
                .help("Save to library")
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 4)
        .background(hovering ? Theme.rowHover : .clear, in: .rect(cornerRadius: Theme.Radius.small))
        .padding(.horizontal, Theme.Space.xxs)
        .onHover { hovering = $0 }
    }
}

struct MenuAction: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundStyle(Theme.secondaryText)
                Text(title).font(.system(size: 12))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 4)
            .background(hovering ? Theme.rowHover : .clear, in: .rect(cornerRadius: Theme.Radius.small))
            .padding(.horizontal, Theme.Space.xxs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
