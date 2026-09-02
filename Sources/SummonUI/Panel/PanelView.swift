import AppKit
import SwiftUI
import SummonKit

/// The summon panel. One field, one list, one preview, and a footer that teaches
/// its own shortcuts. Everything here is reachable without touching the mouse.
public struct PanelView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshotting) private var isSnapshotting
    @State private var focusToken = 0
    @State private var appeared = false

    /// Entrance animation is state-driven, which a synchronous image render never
    /// advances — so treat the panel as already settled while snapshotting.
    private var settled: Bool { appeared || isSnapshotting }

    public static let width: CGFloat = 760
    public static let height: CGFloat = 470

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)

            Group {
                switch model.mode {
                case .search: searchBody
                case .fill(let id): FillFieldsPane(model: model, itemID: id)
                case .unlock(let pending): UnlockPane(model: model, pendingItemID: pending)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Theme.hairline)
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(PanelBackground())
        .clipShape(.rect(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 54)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.quick, value: model.toast)
        .summonTransition(isVisible: settled, reduceMotion: reduceMotion)
        .onAppear { appeared = true; focusToken += 1 }
        .onDisappear { appeared = false }
        .onChange(of: model.mode) { _, _ in focusToken += 1 }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedURLs(providers)
            return true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)

            PanelSearchField(
                text: $model.query,
                placeholder: placeholder,
                focusToken: focusToken,
                onMove: { model.moveSelection(by: $0) },
                onSubmit: handleSubmit,
                onCancel: { model.dismissPanel() },
                onTab: { /* preview focus is visual only; Tab is reserved for fill mode */ },
                onDelete: {}
            )
            .frame(height: 26)

            if !model.parsedQuery.filterChips.isEmpty {
                HStack(spacing: Theme.Space.xxs) {
                    ForEach(model.parsedQuery.filterChips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, Theme.Space.xs)
                            .padding(.vertical, 2)
                            .background(Theme.accentWash, in: .capsule)
                    }
                }
            }

            lockButton
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private var placeholder: String {
        if let app = model.focus.previousApp?.localizedName {
            return "Summon anything for \(app)…"
        }
        return "Summon anything…"
    }

    @ViewBuilder
    private var lockButton: some View {
        if model.vault.isConfigured {
            Button {
                model.toggleLock()
            } label: {
                Image(systemName: model.vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(model.vault.isUnlocked ? Theme.success : Theme.spark)
            }
            .buttonStyle(.plain)
            .help(model.vault.isUnlocked ? "Lock sensitive items" : "Unlock sensitive items")
            .accessibilityLabel(model.vault.isUnlocked ? "Lock vault" : "Unlock vault")
        }
    }

    // MARK: - Search body

    private var searchBody: some View {
        HStack(spacing: 0) {
            resultsList
                .frame(width: Self.width * 0.55)

            Divider().overlay(Theme.hairline)

            if let selected = model.selectedResult {
                previewPane(for: selected)
            } else {
                Color.clear
            }
        }
    }

    private var resultsList: some View {
        Group {
            if model.results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    SnapshotSafeScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            if model.query.isEmpty, model.results.contains(where: { $0.item.isPinned }) {
                                sectionHeader("Pinned")
                            }
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                                if model.query.isEmpty, index > 0,
                                   model.results[index - 1].item.isPinned, !result.item.isPinned {
                                    sectionHeader("Most used")
                                }
                                PanelResultRow(
                                    result: result,
                                    isSelected: index == model.selectedIndex,
                                    index: index,
                                    thumbnailURL: model.thumbnailURL(for: result.id),
                                    onActivate: { model.selectedIndex = index; model.use(result.id) },
                                    onTogglePin: { model.togglePin(result.id) }
                                )
                                .id(result.id)
                                .opacity(settled ? 1 : 0)
                                .animation(
                                    (reduceMotion || isSnapshotting) ? nil
                                        : Theme.gentle.delay(Double(min(index, 12)) * Theme.stagger),
                                    value: appeared
                                )
                            }
                        }
                        .padding(.horizontal, Theme.Space.xs)
                        .padding(.vertical, Theme.Space.xs)
                    }
                    .onChange(of: model.selectedIndex) { _, new in
                        guard model.results.indices.contains(new) else { return }
                        withAnimation(reduceMotion ? nil : Theme.gentle) {
                            proxy.scrollTo(model.results[new].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Theme.tertiaryText)
            .tracking(0.6)
            .padding(.horizontal, Theme.Space.s)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, 2)
    }

    private var emptyState: some View {
        Group {
            if model.store.snapshots.isEmpty {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "Nothing to summon yet",
                    message: "Copy something, then press \(model.settings.quickSaveHotKey.displayString) to save it — or drop a file straight onto this panel."
                )
            } else {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No matches",
                    message: "Try fewer characters, or filter with #tag, /folder, img:, pdf: or txt:."
                )
            }
        }
    }

    private func previewPane(for result: SearchResult) -> some View {
        let data = model.previewData(for: result.id)
        return PanelPreview(
            snapshot: result.item,
            bodyText: data.body,
            fileURL: data.fileURL,
            thumbnailURL: data.thumbnailURL
        )
        .frame(maxWidth: .infinity)
        .id(result.id)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            switch model.mode {
            case .search:
                KeyHint("↩", pasteHintLabel)
                KeyHint("⌘↩", "Copy")
                if model.selectedResult?.item.kind.isBlobBacked == true {
                    KeyHint("⌥↩", "Open")
                }
                KeyHint("⇧↩", "Paste plain")
                Spacer()
                if !Inserter.hasAccessibility && model.settings.autoPaste {
                    Label("Copies until Accessibility is allowed", systemImage: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.spark)
                        .labelStyle(.titleAndIcon)
                }
                KeyHint("⎋", "Close")

            case .fill:
                KeyHint("⇥", "Next field")
                KeyHint("↩", "Insert")
                Spacer()
                KeyHint("⎋", "Back")

            case .unlock:
                Label("Sensitive items stay encrypted until you unlock", systemImage: "lock.shield")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondaryText)
                    .labelStyle(.titleAndIcon)
                Spacer()
                KeyHint("⎋", "Cancel")
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs + 1)
        .frame(height: 30)
    }

    private var pasteHintLabel: String {
        guard let item = model.selectedResult?.item else { return "Insert" }
        if item.isLocked { return "Unlock" }
        if item.hasPlaceholders { return "Fill in" }
        return Inserter.hasAccessibility && model.settings.autoPaste ? "Paste" : "Copy"
    }

    // MARK: - Actions

    private func handleSubmit(_ modifiers: NSEvent.ModifierFlags) {
        guard let result = model.selectedResult else { return }
        if modifiers.contains(.command) {
            model.use(result.id, style: .copy)
        } else if modifiers.contains(.option) {
            model.use(result.id, style: .open)
        } else if modifiers.contains(.shift) {
            model.use(result.id, style: .plainPaste)
        } else {
            model.use(result.id, style: .paste)
        }
    }

    private func loadDroppedURLs(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url") as? Data,
                   let decoded = URL(dataRepresentation: url, relativeTo: nil) {
                    urls.append(decoded)
                }
            }
            guard !urls.isEmpty else { return }
            model.importDroppedFiles(urls)
        }
    }
}
