import AppKit
import Observation
import SwiftUI
import SummonKit

/// What is layered over the results, if anything.
public enum PanelOverlay: Equatable, Sendable {
    case none
    case actions
    case prompt(PromptKind)
    case folderPicker
    case confirmDelete
}

public enum PromptKind: Equatable, Sendable {
    case rename
    case addTag

    public var title: String {
        switch self {
        case .rename: "Rename"
        case .addTag: "Add tag"
        }
    }

    public var placeholder: String {
        switch self {
        case .rename: "New name"
        case .addTag: "Tag name"
        }
    }
}

public struct FolderChoice: Identifiable, Equatable, Sendable {
    public let id: UUID?
    public let label: String
}

/// One row, with the position it occupies in the flattened result list.
public struct DisplayRow: Identifiable, Equatable, Sendable {
    public let index: Int
    public let result: SearchResult
    public var id: UUID { result.id }
}

/// A titled group of rows, ready to render.
public struct DisplaySection: Identifiable, Equatable, Sendable {
    public let title: String?
    public let rows: [DisplayRow]
    public var id: String { title ?? "" }
}

public enum SidebarSelection: Hashable, Sendable {
    case all
    case recents
    case pinned
    case locked
    case clipboard
    case folder(UUID)
    case tag(String)
    case kind(ItemKind)

    /// Identifies the filtered item set for the search cache, so typing within one
    /// selection reuses its index and switching selection rebuilds.
    var cacheToken: String {
        switch self {
        case .all: "all"
        case .recents: "recents"
        case .pinned: "pinned"
        case .locked: "locked"
        case .clipboard: "clipboard"
        case .folder(let id): "folder:\(id)"
        case .tag(let name): "tag:\(name)"
        case .kind(let kind): "kind:\(kind.rawValue)"
        }
    }
}

public enum PanelMode: Equatable {
    case search
    /// A snippet with fill-in fields is being completed before insertion.
    case fill(itemID: UUID)
    /// A locked item was chosen; authenticate, then continue with it.
    case unlock(pendingItemID: UUID?)
}

public struct Toast: Identifiable, Equatable {
    public enum Tone: Equatable { case neutral, success, warning, danger }
    public let id = UUID()
    public var text: String
    public var symbol: String
    public var tone: Tone = .neutral
    public var detail: String?

    public init(text: String, symbol: String, tone: Tone = .neutral, detail: String? = nil) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
        self.detail = detail
    }
}

/// The single object every surface talks to. Owns the services, the panel state and
/// the actions; the windows themselves live in the executable target.
@MainActor
@Observable
public final class AppModel {

    // MARK: - Services

    public let paths: LibraryPaths
    public let vault: Vault
    public let store: LibraryStore
    public let intelligence: Intelligence
    public let clipboard: ClipboardMonitor
    public let inserter: Inserter
    public let focus: FocusTracker
    public let importer: Importer
    public let settings: AppSettings

    // MARK: - Panel state

    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            resetSelection()
            runSearch()
        }
    }
    public private(set) var results: [SearchResult] = []
    /// The same results, grouped for display and carrying each row's absolute
    /// position. The position has to be part of observed state: computed from a side
    /// table during `body`, SwiftUI does not know it changed and happily reuses a row
    /// still showing the number it had under the previous query.
    public private(set) var sections: [DisplaySection] = []
    public var selectedIndex: Int = 0
    public var mode: PanelMode = .search
    public var isPanelVisible: Bool = false
    public var fieldValues: [String: String] = [:]
    public var pinEntry: String = ""
    public var pinError: String?

    // MARK: - ⌘K overlay

    public private(set) var overlay: PanelOverlay = .none
    public var actionQuery: String = "" { didSet { if actionQuery != oldValue { filterActions() } } }
    public private(set) var actionResults: [PanelActionID] = []
    public var actionSelectedIndex: Int = 0
    /// Text being entered for Rename or Add Tag.
    public var promptText: String = ""
    public private(set) var folderChoices: [FolderChoice] = []
    public var folderChoiceIndex: Int = 0

    /// Narrows the search to one folder. Kept separate from the query text because
    /// `/Folder` splits on spaces, so a folder called "Client Replies" cannot be
    /// expressed there at all.
    public private(set) var folderScope: String?

    /// Focus tokens. The search field and the overlay field each watch their own, so
    /// opening or closing the overlay moves first responder without either of them
    /// having to know about the other.
    public private(set) var queryFocusToken = 0
    public private(set) var overlayFocusToken = 0

    /// Which surface owns the keyboard right now.
    public var keyContext: PanelContext {
        switch overlay {
        case .none: break
        case .actions: return .actionMenu
        case .prompt, .folderPicker, .confirmDelete: return .actionMenu
        }
        switch mode {
        case .search: return .results
        case .fill: return .fill
        case .unlock: return .unlock
        }
    }

    // MARK: - Main window state

    public var sidebarSelection: SidebarSelection = .all
    public var mainSelection: UUID?
    public var mainSearch: String = ""
    public var useGridLayout: Bool = false

    // MARK: - Chrome

    public var toast: Toast?
    public var accessibilityPromptShown = false

    // Set by the executable; the model never touches a window directly.
    public var showPanelHandler: (() -> Void)?
    public var hidePanelHandler: (() -> Void)?
    public var showMainWindowHandler: (() -> Void)?
    public var showOnboardingHandler: (() -> Void)?

    /// Owns the search index so it is built when the library changes, not per
    /// keystroke. Not observed — it is a service, not view state.
    @ObservationIgnored public let searchEngine = SearchEngine()

    /// Cached TCC answer. Reading `Inserter.hasAccessibility` directly from a view
    /// body meant a TCC round trip twice per render.
    public let accessibility = AccessibilityStatus()

    /// Held modifiers, on their own observable object so that watching them redraws
    /// the footer and nothing else. See `PanelModifierState`.
    public let modifiers = PanelModifierState()

    private var toastTask: Task<Void, Never>?
    private var autoLockTimer: Timer?

    public init() throws {
        let paths = LibraryPaths.standard()
        self.paths = paths
        let vault = Vault(paths: paths)
        self.vault = vault
        self.store = try LibraryStore(paths: paths, vault: vault)
        self.intelligence = Intelligence()
        self.clipboard = ClipboardMonitor(paths: paths)
        self.inserter = Inserter()
        self.focus = FocusTracker()
        self.settings = AppSettings()
        self.importer = Importer(store: store, intelligence: intelligence)

        applySettings()
        startAutoLockTimer()
        runSearch()

        // A failure that only reaches the log is a failure the person using the app
        // never finds out about — and for a save, that means a lost edit.
        store.onError = { [weak self] message in
            self?.show(Toast(text: message, symbol: "exclamationmark.triangle", tone: .danger))
        }
    }

    public func applySettings() {
        vault.autoLockMinutes = settings.autoLockMinutes
        intelligence.isEnabled = settings.intelligenceEnabled
        clipboard.maxEntries = settings.clipboardLimit
        clipboard.persistBetweenLaunches = settings.clipboardPersists
        clipboard.isEnabled = settings.clipboardHistoryEnabled
        if settings.clipboardHistoryEnabled { clipboard.start() } else { clipboard.stop() }
    }

    // MARK: - Search

    public var parsedQueryWithScope: Query {
        var parsed = Query.parse(query)
        if let folderScope { parsed.folder = folderScope }
        return parsed
    }

    public func runSearch() {
        let ranked = searchEngine.sections(parsedQueryWithScope,
                                           snapshots: store.snapshots,
                                           revision: store.revision,
                                           frontmostBundleID: focus.previousBundleID,
                                           frontmostAppName: focus.previousApp?.localizedName)
        results = ranked.allResults

        // Absolute positions assigned once, here, so ⌘-numbering runs across sections
        // rather than restarting in each one.
        var position = 0
        sections = ranked.map { section in
            let rows = section.results.map { result -> DisplayRow in
                defer { position += 1 }
                return DisplayRow(index: position, result: result)
            }
            return DisplaySection(title: section.title, rows: rows)
        }
        if selectedIndex >= results.count { selectedIndex = max(0, results.count - 1) }
    }

    // MARK: - Main window keyboard
    //
    // The grid was mouse-only: ItemCard had a tap gesture and nothing else, so an
    // entire view mode was unreachable from the keyboard.

    /// Moves the library selection by `delta` positions through the visible items.
    public func moveMainSelection(by delta: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let current = items.firstIndex(where: { $0.id == mainSelection }) else {
            mainSelection = items.first?.id
            return
        }
        let next = min(max(0, current + delta), items.count - 1)
        mainSelection = items[next].id
    }

    /// The items the library is currently showing, in display order.
    public var visibleItems: [ItemSnapshot] { itemsForSidebar() }

    public func toggleActions() {
        if case .none = overlay { openActionMenu() } else { closeOverlay() }
    }

    public var mainSelectionIsPinned: Bool {
        mainSelection.flatMap { id in store.snapshots.first { $0.id == id }?.isPinned } ?? false
    }

    public func requestDeleteSelected() {
        guard actionTarget != nil else { return }
        overlay = .confirmDelete
    }

    /// Routes a chord in the library window. Returns false to let the window have it.
    @discardableResult
    public func routeMainWindow(_ chord: KeyChord, columns: Int) -> Bool {
        switch (chord.key, chord.modifiers) {
        case (.character("k"), .command):
            guard mainSelection != nil else { return false }
            if case .none = overlay { openActionMenu() } else { closeOverlay() }
            return true
        case (.down, []): moveMainSelection(by: useGridLayout ? columns : 1); return true
        case (.up, []): moveMainSelection(by: useGridLayout ? -columns : -1); return true
        case (.right, []) where useGridLayout: moveMainSelection(by: 1); return true
        case (.left, []) where useGridLayout: moveMainSelection(by: -1); return true
        case (.character("p"), .command):
            guard let id = mainSelection else { return false }
            togglePin(id); return true
        case (.delete, .command):
            guard mainSelection != nil else { return false }
            overlay = .confirmDelete; return true
        default: return false
        }
    }

    /// Ranking changed, so the old position means nothing: go back to the best match.
    /// Without this, refining a query while sitting on row 5 leaves you on row 5 of a
    /// different list — and the next Return pastes something you never looked at.
    private func resetSelection() { selectedIndex = 0 }

    public var selectedResult: SearchResult? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    public var parsedQuery: Query { Query.parse(query) }

    public func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(0, selectedIndex + delta), results.count - 1)
    }

    public func selectFirst() { selectedIndex = 0 }
    public func selectLast() { selectedIndex = max(0, results.count - 1) }

    // MARK: - Keyboard

    /// Resolves a chord and performs it. Returns false when the panel does not claim
    /// the key, so it falls through to the text field.
    @discardableResult
    public func route(_ chord: KeyChord) -> Bool {
        guard let command = PanelKeyMap.command(for: chord,
                                                in: keyContext,
                                                queryIsEmpty: parsedQueryWithScope.text.isEmpty,
                                                selectionIsFolder: selectionHasFolder) else { return false }
        perform(command)
        return true
    }

    /// The field editor's path. Unmodified editing keys arrive as selectors.
    @discardableResult
    public func routeFieldSelector(_ selector: Selector, fieldIsEmpty: Bool) -> Bool {
        guard let key = PanelKeyRouter.key(for: selector) else { return false }
        let modifiers = KeyModifiers(NSApp.currentEvent?.modifierFlags ?? [])
        guard let command = PanelKeyMap.command(for: KeyChord(key, modifiers),
                                                in: keyContext,
                                                queryIsEmpty: fieldIsEmpty,
                                                selectionIsFolder: selectionHasFolder) else { return false }
        perform(command)
        return true
    }

    /// ⇥ needs somewhere to go: the selected item must sit in a folder, and we must
    /// not already be scoped to one.
    private var selectionHasFolder: Bool {
        folderScope == nil && selectedResult?.item.folderPath.isEmpty == false
    }

    /// The one place a key press turns into behaviour, so the panel, the action menu
    /// and the fill form cannot drift apart in what a key means.
    public func perform(_ command: PanelCommand) {
        switch command {
        case .move(let delta):
            if keyContext == .actionMenu { moveOverlaySelection(by: delta) } else { moveSelection(by: delta) }
        case .selectFirst: selectFirst()
        case .selectLast: selectLast()
        case .activate(let style):
            guard let result = selectedResult else { return }
            use(result.id, style: style)
        case .activateIndex(let index):
            guard results.indices.contains(index) else { return }
            selectedIndex = index
            use(results[index].id)
        case .toggleActionMenu:
            if case .none = overlay { openActionMenu() } else { closeOverlay() }
        case .runSelectedAction: runSelectedOverlayItem()
        case .escape: escape()
        case .drillIn: drillIn()
        case .drillOut: drillOut()
        case .nextField, .previousField: break   // handled by SwiftUI focus in fill mode
        case .action(let action): run(action)
        }
    }

    /// Pops exactly one level per press. Previously ⎋ was handled in two places that
    /// both went straight to dismissPanel, so there was nowhere to add a level.
    public func escape() {
        if overlay != .none { closeOverlay(); return }
        if mode != .search { mode = .search; queryFocusToken += 1; return }
        if !query.isEmpty { query = ""; return }
        if folderScope != nil { drillOut(); return }
        dismissPanel()
    }

    // MARK: - Folder scope

    public func drillIn() {
        guard let folder = selectedResult?.item.folderPath.last else { return }
        folderScope = folder
        query = ""
        selectedIndex = 0
        runSearch()
    }

    public func drillOut() {
        guard folderScope != nil else { return }
        folderScope = nil
        selectedIndex = 0
        runSearch()
    }

    // MARK: - ⌘K overlay

    public func openActionMenu() {
        guard actionTarget != nil else { return }
        overlay = .actions
        actionQuery = ""
        actionSelectedIndex = 0
        filterActions()
        overlayFocusToken += 1
    }

    public func closeOverlay() {
        overlay = .none
        actionQuery = ""
        promptText = ""
        queryFocusToken += 1
    }

    /// The item the ⌘K menu is acting on: the panel's selection when the panel is up,
    /// the library's otherwise.
    public var actionTarget: ItemSnapshot? {
        if isPanelVisible { return selectedResult?.item }
        return mainSelection.flatMap { id in store.snapshots.first { $0.id == id } }
    }

    private func filterActions() {
        guard let item = actionTarget else { actionResults = []; return }
        let all = PanelKeyMap.actions(isBlobBacked: item.kind.isBlobBacked, isLocked: item.isLocked)
        let needle = actionQuery.lowercased()
        actionResults = needle.isEmpty ? all : all.filter { $0.title.lowercased().contains(needle) }
        actionSelectedIndex = min(actionSelectedIndex, max(0, actionResults.count - 1))
    }

    private func moveOverlaySelection(by delta: Int) {
        switch overlay {
        case .actions:
            guard !actionResults.isEmpty else { return }
            actionSelectedIndex = min(max(0, actionSelectedIndex + delta), actionResults.count - 1)
        case .folderPicker:
            guard !folderChoices.isEmpty else { return }
            folderChoiceIndex = min(max(0, folderChoiceIndex + delta), folderChoices.count - 1)
        default: break
        }
    }

    private func runSelectedOverlayItem() {
        switch overlay {
        case .actions:
            guard actionResults.indices.contains(actionSelectedIndex) else { return }
            run(actionResults[actionSelectedIndex])
        case .prompt(let kind):
            commitPrompt(kind)
        case .folderPicker:
            guard folderChoices.indices.contains(folderChoiceIndex) else { return }
            commitMove(to: folderChoices[folderChoiceIndex].id)
        case .confirmDelete:
            guard let id = actionTarget?.id else { return }
            closeOverlay()
            deleteItem(id)
        case .none:
            break
        }
    }

    /// The label the panel's title bar shows above the overlay.
    public var overlayTitle: String {
        switch overlay {
        case .none, .actions: "Actions"
        case .prompt(let kind): kind.title
        case .folderPicker: "Move to folder"
        case .confirmDelete: "Delete"
        }
    }

    public func run(_ action: PanelActionID) {
        guard let target = actionTarget else { return }
        let id = target.id
        switch action {
        case .paste: closeOverlay(); use(id, style: .paste)
        case .pastePlain: closeOverlay(); use(id, style: .plainPaste)
        case .copy: closeOverlay(); use(id, style: .copy)
        case .open: closeOverlay(); use(id, style: .open)
        case .reveal: closeOverlay(); revealInFinder(id)
        case .togglePin: closeOverlay(); togglePin(id)
        case .toggleSensitive:
            closeOverlay()
            setItemSensitive(id, !target.isSensitive)
        case .delete:
            overlay = .confirmDelete
        case .rename:
            promptText = target.title
            overlay = .prompt(.rename)
            overlayFocusToken += 1
        case .addTag:
            promptText = ""
            overlay = .prompt(.addTag)
            overlayFocusToken += 1
        case .move:
            folderChoices = [FolderChoice(id: nil, label: "No folder")]
                + store.allFolders()
                    .sorted { $0.path.joined() .localizedStandardCompare($1.path.joined()) == .orderedAscending }
                    .map { FolderChoice(id: $0.id, label: $0.path.joined(separator: " › ")) }
            folderChoiceIndex = 0
            overlay = .folderPicker
            overlayFocusToken += 1
        }
    }

    private func commitPrompt(_ kind: PromptKind) {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = selectedResult?.id, let item = store.item(id: id) else {
            closeOverlay(); return
        }
        switch kind {
        case .rename: store.rename(item, to: text)
        case .addTag:
            // Normalised and de-duplicated by setTags, so adding a tag twice is a
            // no-op rather than a duplicate chip.
            store.setTags(item, names: item.tagNames + [text])
        }
        closeOverlay()
        runSearch()
    }

    private func commitMove(to folderID: UUID?) {
        guard let id = selectedResult?.id, let item = store.item(id: id) else { closeOverlay(); return }
        let folder = folderID.flatMap { target in store.allFolders().first { $0.id == target } }
        store.move(item, to: folder)
        closeOverlay()
        runSearch()
        show(Toast(text: folder.map { "Moved to \($0.name)" } ?? "Removed from folder",
                   symbol: "folder", tone: .neutral))
    }

    // MARK: - Summoning

    public func summon() {
        // Capture the frontmost app *before* the panel takes focus, so we know where
        // to put the content back and which app to bias the ranking toward.
        focus.capture()
        accessibility.refresh()
        query = ""
        selectedIndex = 0
        mode = .search
        // Both of these used to persist: drill into a folder, dismiss, summon again,
        // and you were still scoped to it with no memory of why. Same for a ⌘K menu
        // left open when the panel was dismissed.
        folderScope = nil
        overlay = .none
        fieldValues = [:]
        pinEntry = ""
        pinError = nil
        // No store.refresh() here: every mutating method and both vault transitions
        // already refresh, so the snapshots are current. Refreshing again cost a full
        // fetch plus a decrypt of every sealed item before the window appeared.
        runSearch()
        isPanelVisible = true
        showPanelHandler?()
    }

    public func dismissPanel() {
        isPanelVisible = false
        mode = .search
        hidePanelHandler?()
        FileStore.clearScratch()
    }

    // MARK: - Using an item

    /// Defined in SummonKit so `PanelKeyMap` can name it; aliased here so every
    /// existing `model.use(id, style:)` call site is unchanged.
    public typealias UseStyle = ActivationStyle

    public func use(_ id: UUID, style: UseStyle = .paste) {
        guard let snapshot = store.snapshots.first(where: { $0.id == id }) else { return }

        if snapshot.isLocked {
            mode = .unlock(pendingItemID: id)
            pinEntry = ""
            pinError = nil
            Task { await tryBiometricUnlock() }
            return
        }

        if snapshot.hasPlaceholders, style != .open, let template = store.template(for: id) {
            fieldValues = Dictionary(uniqueKeysWithValues: template.fields.map {
                ($0.name, $0.defaultValue ?? "")
            })
            mode = .fill(itemID: id)
            return
        }

        deliver(id, style: style)
    }

    public func completeFill(for id: UUID, style: UseStyle = .paste) {
        deliver(id, style: style)
    }

    private func deliver(_ id: UUID, style: UseStyle) {
        let clipboardText = inserter.currentClipboardText()
        guard let payload = store.payload(for: id, fieldValues: fieldValues, clipboard: clipboardText) else {
            show(Toast(text: "Couldn’t read that item", symbol: "exclamationmark.triangle", tone: .danger))
            return
        }

        let bundleID = focus.previousBundleID

        switch style {
        case .open:
            if let url = payload.fileURL {
                NSWorkspace.shared.open(url)
                store.recordUse(id: id, inApp: bundleID)
                dismissPanel()
            } else {
                show(Toast(text: "That item isn’t a file", symbol: "doc.questionmark", tone: .warning))
            }
            return

        case .copy:
            clipboard.ignoreNextChange()
            inserter.writeToPasteboard(payload)
            store.recordUse(id: id, inApp: bundleID)
            dismissPanel()
            show(Toast(text: "Copied", symbol: "doc.on.clipboard", tone: .success,
                       detail: "Press ⌘V wherever you need it"))
            return

        case .paste, .plainPaste:
            let plainOnly = style == .plainPaste
            clipboard.ignoreNextChange()
            dismissPanel()
            let autoPaste = settings.autoPaste
            Task { [inserter, focus, store] in
                let outcome = await inserter.insert(payload, into: focus,
                                                    plainOnly: plainOnly, autoPaste: autoPaste)
                store.recordUse(id: id, inApp: bundleID)
                switch outcome {
                case .pasted:
                    break // The content landing where the cursor was is its own confirmation.
                case .copiedOnly:
                    self.offerAccessibilityOrConfirmCopy()
                case .failed(let message):
                    self.show(Toast(text: message, symbol: "exclamationmark.triangle", tone: .danger))
                }
            }
        }
    }

    private func offerAccessibilityOrConfirmCopy() {
        if Inserter.hasAccessibility || !settings.autoPaste {
            show(Toast(text: "Copied", symbol: "doc.on.clipboard", tone: .success,
                       detail: "Press ⌘V wherever you need it"))
        } else {
            show(Toast(text: "Copied — press ⌘V", symbol: "doc.on.clipboard", tone: .warning,
                       detail: "Allow Accessibility to have Summon paste for you"))
            // Ask once per launch, and only after it would have helped.
            if !accessibilityPromptShown {
                accessibilityPromptShown = true
                Inserter.requestAccessibility()
            }
        }
    }

    // MARK: - Dragging

    /// The provider behind a dragged row. Files drag as files; snippets drag as their
    /// rendered text, with formatting when they have it. Locked items refuse to drag,
    /// which is the same rule the insert path follows.
    public func dragProvider(for id: UUID) -> NSItemProvider? {
        guard let snapshot = store.snapshots.first(where: { $0.id == id }), !snapshot.isLocked else {
            return nil
        }
        guard let payload = store.payload(for: id, clipboard: inserter.currentClipboardText()) else {
            return nil
        }
        return DragProvider.make(for: payload, title: snapshot.title)
    }

    // MARK: - Vault

    public func tryBiometricUnlock() async {
        guard vault.biometricsEnabled else { return }
        do {
            try await vault.unlockWithBiometrics()
            afterUnlock()
        } catch {
            // Silent: the PIN field is already on screen as the fallback.
            Log.vault.info("Biometric unlock declined or failed.")
        }
    }

    public func submitPIN() {
        do {
            try vault.unlock(pin: pinEntry)
            afterUnlock()
        } catch {
            pinError = (error as? VaultError)?.errorDescription ?? error.localizedDescription
            pinEntry = ""
        }
    }

    private func afterUnlock() {
        pinEntry = ""
        pinError = nil
        store.refresh()
        runSearch()
        if case .unlock(let pending) = mode {
            mode = .search
            if let pending { use(pending) }
        } else {
            mode = .search
        }
    }

    public func lockVault() {
        vault.lock()
        FileStore.clearScratch()
        // A decoded thumbnail of a sensitive item must not outlive the unlock that
        // produced it — clearing the scratch files is not enough on its own.
        ThumbnailCache.shared.invalidateAll()
        store.refresh()
        runSearch()
        show(Toast(text: "Locked", symbol: "lock.fill", tone: .neutral))
    }

    public func toggleLock() {
        if vault.isUnlocked { lockVault() } else { mode = .unlock(pendingItemID: nil) }
    }

    private func startAutoLockTimer() {
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.vault.lockIfIdle() {
                    FileStore.clearScratch()
                    self.store.refresh()
                    self.runSearch()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoLockTimer = timer
    }

    // MARK: - Quick actions

    public func togglePin(_ id: UUID) {
        store.togglePinned(id: id)
        runSearch()
        let pinned = store.snapshots.first { $0.id == id }?.isPinned ?? false
        show(Toast(text: pinned ? "Pinned" : "Unpinned", symbol: pinned ? "pin.fill" : "pin.slash", tone: .neutral))
    }

    public func revealInFinder(_ id: UUID) {
        guard let item = store.item(id: id), let blob = item.storedBlob,
              let url = try? store.files.materialize(blob, itemID: id, key: vault.currentKey) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func deleteItem(_ id: UUID) {
        guard let item = store.item(id: id) else { return }
        let title = item.title
        store.delete(item)
        runSearch()
        show(Toast(text: "Deleted “\(title)”", symbol: "trash", tone: .neutral))
    }

    /// Set by the app so Settings and onboarding can re-register shortcuts after a change.
    public var reregisterHotKeysHandler: (() -> Void)?

    public func reregisterHotKeys() { reregisterHotKeysHandler?() }

    // MARK: - Sensitivity

    /// Marking something sensitive means re-encrypting it, which needs the vault open.
    /// If there is no PIN yet, this is the moment to offer setting one.
    public func setItemSensitive(_ id: UUID, _ sensitive: Bool) {
        guard let item = store.item(id: id) else { return }
        guard requireUnlockedVault() else { return }
        do {
            try store.setSensitive(item, sensitive)
            runSearch()
            show(Toast(text: sensitive ? "Encrypted and locked" : "No longer sensitive",
                       symbol: sensitive ? "lock.fill" : "lock.open.fill", tone: .success))
        } catch {
            show(Toast(text: "Couldn’t change that", symbol: "exclamationmark.triangle",
                       tone: .danger, detail: error.localizedDescription))
        }
    }

    public func setFolderSensitive(_ folder: SummonFolder, _ sensitive: Bool) {
        guard requireUnlockedVault() else { return }
        do {
            try store.setFolderSensitive(folder, sensitive)
            runSearch()
            show(Toast(text: sensitive ? "Folder encrypted" : "Folder no longer sensitive",
                       symbol: sensitive ? "lock.fill" : "lock.open.fill", tone: .success))
        } catch {
            show(Toast(text: "Couldn’t change that", symbol: "exclamationmark.triangle",
                       tone: .danger, detail: error.localizedDescription))
        }
    }

    /// Returns true when the vault is ready to encrypt. Otherwise it steers the user
    /// to the thing they need to do next rather than failing silently.
    public func requireUnlockedVault() -> Bool {
        if vault.isUnlocked { return true }
        if !vault.isConfigured {
            needsPINSetup = true
            return false
        }
        mode = .unlock(pendingItemID: nil)
        if !isPanelVisible { summonForUnlock() }
        return false
    }

    /// Set when an action needs a PIN that does not exist yet; Settings picks this up.
    public var needsPINSetup = false

    public func summonForUnlock() {
        focus.capture()
        query = ""
        mode = .unlock(pendingItemID: nil)
        isPanelVisible = true
        showPanelHandler?()
        Task { await tryBiometricUnlock() }
    }

    // MARK: - Capture

    public func quickSaveSelection() {
        Task {
            let capture = SelectionCapture(inserter: inserter)
            let selection = await capture.capture()
            let created = await importer.importSelection(selection)
            runSearch()
            if created.isEmpty {
                show(Toast(text: "Nothing selected to save", symbol: "questionmark.circle", tone: .warning,
                           detail: "Select text or files, then press \(settings.quickSaveHotKey.displayString)"))
            } else if created.count == 1 {
                show(Toast(text: "Saved “\(created[0].title)”", symbol: "sparkles", tone: .success))
            } else {
                show(Toast(text: "Saved \(created.count) items", symbol: "sparkles", tone: .success))
            }
        }
    }

    public func saveClipboardEntry(_ entry: ClipboardMonitor.Entry) {
        Task {
            if let item = await importer.importClipboardEntry(entry) {
                runSearch()
                show(Toast(text: "Saved “\(item.title)”", symbol: "sparkles", tone: .success))
            }
        }
    }

    public func saveCurrentClipboard() {
        guard let entry = clipboard.entries.first else {
            show(Toast(text: "Clipboard is empty", symbol: "clipboard", tone: .warning))
            return
        }
        saveClipboardEntry(entry)
    }

    public func importDroppedFiles(_ urls: [URL], into folder: SummonFolder? = nil) {
        Task {
            let created = await importer.importFiles(urls, into: folder)
            runSearch()
            // Nothing imported is not a success. This used to announce
            // "Added 0 items" in the success tone when every file had failed.
            guard !created.isEmpty else {
                show(Toast(text: urls.count == 1 ? "Couldn’t add that file" : "Couldn’t add those files",
                           symbol: "exclamationmark.triangle", tone: .danger))
                return
            }
            if created.count < urls.count {
                show(Toast(text: "Added \(created.count) of \(urls.count)",
                           symbol: "tray.and.arrow.down", tone: .warning))
                return
            }
            show(Toast(text: created.count == 1 ? "Added “\(created[0].title)”" : "Added \(created.count) items",
                       symbol: "tray.and.arrow.down.fill", tone: .success))
        }
    }

    // MARK: - Creation actions

    public var pendingNewSnippet = false
    public var pendingNewFolder = false

    public func beginNewSnippet() {
        showMainWindowHandler?()
        pendingNewSnippet = true
    }

    public func beginNewFolder() {
        showMainWindowHandler?()
        pendingNewFolder = true
    }

    /// The one place a file chooser is opened, so import behaves identically
    /// whether it arrives by drag, menu, Services, or hotkey.
    public func presentImportPanel(into folder: SummonFolder? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add to Summon"
        panel.message = "Choose files to add to your library. Summon copies them, so moving the originals later is safe."
        guard panel.runModal() == .OK else { return }
        importDroppedFiles(panel.urls, into: folder)
    }

    public func seedStarterLibraryIfEmpty() async {
        await StarterLibrary.seed(into: store, importer: importer)
        runSearch()
    }

    // MARK: - Toasts

    public func show(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }

    // MARK: - Preview resolution

    public struct PreviewData {
        public var body: String?
        public var fileURL: URL?
        public var thumbnailURL: URL?
    }

    /// Everything the preview pane needs. Non-sensitive blobs are read straight from
    /// their library path; only sealed content is decrypted to a scratch file.
    public func previewData(for id: UUID) -> PreviewData {
        guard let item = store.item(id: id) else { return PreviewData() }
        let key = vault.currentKey
        if item.isEffectivelySensitive && key == nil { return PreviewData() }

        var data = PreviewData()
        data.thumbnailURL = thumbnailURL(for: id)

        if item.kind.isTextual {
            data.body = store.resolveBodyText(item, key: key)
        } else if let blob = item.storedBlob {
            data.fileURL = blob.isSealed
                ? try? store.files.materialize(blob, itemID: id, key: key)
                : store.files.location(of: blob)
            if data.body == nil {
                data.body = store.resolveExtractedText(item, key: key)
            }
        }
        return data
    }

    public func thumbnailURL(for id: UUID) -> URL? {
        let url = store.files.thumbnailURL(itemID: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The path a thumbnail *would* live at, without touching the filesystem.
    /// `ThumbnailCache` learns whether it exists by trying to decode it once, so rows
    /// no longer stat the disk on every render.
    public func thumbnailPath(for id: UUID) -> URL {
        store.files.thumbnailURL(itemID: id)
    }

    // MARK: - Derived collections for the main window

    public func itemsForSidebar() -> [ItemSnapshot] {
        var items = store.snapshots
        switch sidebarSelection {
        case .all:
            break
        case .recents:
            items = items.filter { $0.lastUsedAt != nil }
                .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
        case .pinned:
            items = items.filter(\.isPinned)
        case .locked:
            items = items.filter(\.isSensitive)
        case .clipboard:
            return []
        case .folder(let id):
            guard let folder = store.allFolders().first(where: { $0.id == id }) else { return [] }
            let ids = Set(folder.allItems().map(\.id))
            items = items.filter { ids.contains($0.id) }
        case .tag(let name):
            items = items.filter { $0.tagNames.contains(name) }
        case .kind(let kind):
            items = items.filter { $0.kind == kind }
        }

        if !mainSearch.isEmpty {
            let ranked = searchEngine.searchFiltered(mainSearch,
                                                     snapshots: items,
                                                     revision: store.revision,
                                                     token: sidebarSelection.cacheToken)
            return ranked.map(\.item)
        }
        if case .recents = sidebarSelection { return items }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    public var sidebarTitle: String {
        switch sidebarSelection {
        case .all: "All Items"
        case .recents: "Recents"
        case .pinned: "Pinned"
        case .locked: "Sensitive"
        case .clipboard: "Clipboard"
        case .folder(let id): store.allFolders().first { $0.id == id }?.name ?? "Folder"
        case .tag(let name): "#\(name)"
        case .kind(let kind): kind.pluralName
        }
    }
}
