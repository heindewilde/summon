import AppKit
import SwiftUI
import SummonKit
import SummonUI

/// The summon panel. One field, one list, a preview when it earns its place, and a
/// footer that teaches its own shortcuts. Everything here is reachable without the
/// mouse.
public struct PanelView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshotting) private var isSnapshotting
    @State private var appeared = false
    /// Resolved off the render path. Never call previewData(for:) from `body`.
    @State private var preview: AppModel.PreviewData?
    /// Debounced. `needsPreview` flips per row; this only follows once you stop on one.
    @State private var showPreview = false

    /// Entrance is state-driven, which a synchronous image render never advances — so
    /// treat the panel as already settled while snapshotting.
    private var settled: Bool { appeared || isSnapshotting }

    public static let width: CGFloat = 750
    public static let height: CGFloat = 475

    /// The list keeps the full width until the selection is something you actually
    /// need to look at.
    private static let listFraction: CGFloat = 0.60

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Rule()

            Group {
                switch model.mode {
                case .search: searchBody
                case .fill(let id): FillFieldsPane(model: model, itemID: id)
                case .unlock(let pending): UnlockPane(model: model, pendingItemID: pending)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rule()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(PanelBackground())
        .clipShape(.rect(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .overlay {
            // A scrim while ⌘K is open, so the menu reads as the thing in front and
            // the eye is not asked to parse two lists at once.
            if model.overlay != .none {
                Rectangle()
                    .fill(.black.opacity(0.22))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.overlay != .none {
                ActionMenu(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.sheet, value: model.overlay)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 52)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Theme.panelIn, value: model.toast)
        .summonTransition(isVisible: settled, reduceMotion: reduceMotion)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadDroppedURLs(providers)
            return true
        }
        .onChange(of: model.results.count) { _, count in
            guard model.isPanelVisible else { return }
            let message = count == 0
                ? "No matches"
                : "\(count) result\(count == 1 ? "" : "s"), \(model.results[0].item.title) first"
            AccessibilityNotification.Announcement(message).post()
        }
        .task(id: model.selectedResult?.id) {
            guard let id = model.selectedResult?.id else {
                preview = nil
                showPreview = false
                return
            }
            // Collapsing is immediate; opening waits. Arrowing past an image should
            // not flash the pane open for one frame, but a list that stays wide while
            // you scroll past a PDF is never wrong — it just has not opened yet.
            if !needsPreview { showPreview = false }
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            preview = model.previewData(for: id)

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            showPreview = needsPreview
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Icon.large)
                .foregroundStyle(Theme.tertiaryText)
                .accessibilityHidden(true)

            PanelSearchField(
                text: $model.query,
                placeholder: placeholder,
                focusToken: model.queryFocusToken,
                route: { selector, isEmpty in
                    model.routeFieldSelector(selector, fieldIsEmpty: isEmpty)
                }
            )
            .frame(height: 24)

            ForEach(model.parsedQuery.filterChips, id: \.self) { chip in
                Text(chip)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, Theme.Space.s)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(Theme.surface, in: .capsule)
            }

            lockButton
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 52)
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
                Image(systemName: model.vault.isUnlocked ? "lock.open" : "lock.fill")
                    .font(Theme.Icon.regular)
                    .foregroundStyle(model.vault.isUnlocked ? Theme.tertiaryText : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(model.vault.isUnlocked ? "Lock sensitive items" : "Unlock sensitive items")
            .accessibilityLabel(model.vault.isUnlocked ? "Lock vault" : "Unlock vault")
        }
    }

    // MARK: - Search body

    /// A preview only when seeing it is what decides the choice. A snippet's body is
    /// already on its row; an image or a PDF is not.
    private var needsPreview: Bool {
        guard let item = model.selectedResult?.item else { return false }
        if item.isLocked { return false }
        switch item.kind {
        case .image, .document, .file: return true
        case .text, .richText: return item.previewLine.count > 60
        }
    }

    private var searchBody: some View {
        HStack(spacing: 0) {
            resultsList
                .frame(maxWidth: showPreview ? Self.width * Self.listFraction : .infinity)

            if showPreview, let selected = model.selectedResult {
                Rule()
                PanelPreview(
                    snapshot: selected.item,
                    bodyText: preview?.body,
                    fileURL: preview?.fileURL,
                    thumbnailURL: preview?.thumbnailURL
                )
                .frame(maxWidth: .infinity)
                .id(selected.id)
            }
        }
        .animation(reduceMotion ? nil : Theme.previewSplit, value: showPreview)
    }

    @ViewBuilder
    private var resultsList: some View {
        if model.results.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                SnapshotSafeScrollView {
                    SnapshotSafeLazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.sections) { section in
                            if let title = section.title {
                                sectionHeader(title)
                            }
                            ForEach(section.rows) { row in
                                PanelResultRow(
                                    result: row.result,
                                    isSelected: row.index == model.selectedIndex,
                                    index: row.index,
                                    onActivate: {
                                        model.selectedIndex = row.index
                                        model.use(row.result.id)
                                    },
                                    onTogglePin: { model.togglePin(row.result.id) },
                                    dragProvider: { model.dragProvider(for: row.result.id) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, Theme.Space.xs)
                }
                // Unanimated on purpose: the search behind this completes in half a
                // millisecond, and an animated scroll would be the slowest thing left.
                .onChange(of: model.selectedIndex) { _, new in
                    guard model.results.indices.contains(new) else { return }
                    // No anchor: scroll the minimum needed to bring the row into
                    // view. `.center` re-centred the list on every arrow press even
                    // when the next row was already visible, which is half of why
                    // moving through results felt jumpy.
                    proxy.scrollTo(model.results[new].id)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        SectionHeader(title)
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xs)
    }

    private var emptyState: some View {
        Group {
            if model.store.snapshots.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: "Nothing to summon yet",
                    message: "Copy something, then press \(MacSettings.shared.quickSaveHotKey.displayString) to save it — or drop a file straight onto this panel."
                )
            } else {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No matches",
                    message: "Try fewer characters, or filter with #tag, /folder, img:, pdf: or txt:."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.l) {
            switch model.mode {
            case .search:
                if let scope = model.folderScope {
                    Label(scope, systemImage: "folder")
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.secondaryText)
                        .labelStyle(.titleAndIcon)
                    KeyHint("⌫", "Back")
                } else {
                    SummonMarkShape()
                        .fill(
                            LinearGradient(colors: [Theme.Brand.violetBright, Theme.accent],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 13, height: 13)
                        .glow(Theme.accent, radius: 6, strength: 0.7)
                        .accessibilityHidden(true)
                    Text("Summon")
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                if !model.accessibility.isTrusted && model.settings.autoPaste {
                    Label("Copies until Accessibility is allowed", systemImage: "info.circle")
                        .font(Theme.Typography.meta)
                        .foregroundStyle(Theme.warning)
                        .labelStyle(.titleAndIcon)
                }
                // Reads model.modifiers.held, so holding ⌘ redraws this strip and
                // nothing else. See PanelModifierState.
                PanelFooterHints(modifiers: model.modifiers,
                                 defaultLabel: pasteHintLabel,
                                 canOpen: model.selectedResult?.item.kind.isBlobBacked == true,
                                 canDrillIn: model.selectedResult?.item.folderPath.isEmpty == false
                                     && model.folderScope == nil)

            case .fill:
                KeyHint("⇥", "Next field")
                Spacer()
                KeyHint("↩", "Insert")
                KeyHint("⎋", "Back")

            case .unlock:
                Label("Sensitive items stay encrypted until you unlock", systemImage: "lock.shield")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.secondaryText)
                    .labelStyle(.titleAndIcon)
                Spacer()
                KeyHint("⎋", "Cancel")
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 40)
    }

    private var pasteHintLabel: String {
        guard let item = model.selectedResult?.item else { return "Insert" }
        if item.isLocked { return "Unlock" }
        if item.hasPlaceholders { return "Fill in" }
        return model.accessibility.isTrusted && model.settings.autoPaste ? "Paste" : "Copy"
    }

    // MARK: - Actions


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
