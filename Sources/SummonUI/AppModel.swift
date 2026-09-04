import AppKit
import Observation
import SwiftUI
import SummonKit

public struct FolderDropTarget: Equatable, Sendable {
    public let folderID: UUID
    public let zone: FolderDropZone
    public init(folderID: UUID, zone: FolderDropZone) {
        self.folderID = folderID
        self.zone = zone
    }
}

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
    /// The folder's own icon, so a picker row looks like its row in the sidebar.
    public var symbolName: String = "folder"
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
    /// What this machine can do. Protocols rather than the AppKit-backed classes
    /// this used to construct itself — see `PlatformServices`.
    @ObservationIgnored public let services: PlatformServices
    public var clipboard: any ClipboardService { services.clipboard }
    public var inserter: any InsertionService { services.insertion }
    public var focus: any FocusService { services.focus }
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
    public var secretEntry: String = ""
    public var secretError: String?

    /// True while a secret is being derived.
    ///
    /// Key derivation is deliberately slow — a few hundred milliseconds — and it no
    /// longer blocks the main thread, which means the field stays live while it runs.
    /// Every entry point checks this so a held return key cannot queue five unlock
    /// attempts and burn the whole cooldown allowance on one impatient press.
    public private(set) var isBusy = false

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

    /// Which folder row is currently showing a drop indicator, and what the drop
    /// would do. One value for the whole sidebar: with a `@State` per row, a row that
    /// never received `dropExited` — exactly what happens when the drop lands on a
    /// different row — kept its indicator on screen afterwards.
    public private(set) var folderDropTarget: FolderDropTarget?

    /// The same, for the item list's insertion line.
    public private(set) var itemDropTarget: ItemDropTarget?

    /// When a drop delegate last said anything. Not observed: it exists to notice
    /// silence, and waking every row to say "still dragging" is exactly the cost this
    /// is here to avoid.
    @ObservationIgnored private var dropHeartbeat = Date()
    @ObservationIgnored private var dropWatchdog: Task<Void, Never>?

    /// The one way the drop indicators change.
    ///
    /// Two things go through here that used to be missing. It refuses to write an
    /// unchanged value — `dropUpdated` fires continuously while you drag, and each
    /// write rebuilt the entire sidebar, which is what made dragging feel heavy. And
    /// it keeps the watchdog below alive, which is what finally clears an indicator
    /// after a drag that ends somewhere no delegate hears about.
    public func setFolderDropTarget(_ target: FolderDropTarget?) {
        dropHeartbeat = Date()
        if folderDropTarget != target { folderDropTarget = target }
        if target != nil { startDropWatchdog() }
    }

    /// Set by the drag harness to watch a drop go through, stage by stage. Nil in
    /// normal use; the delegates call it and otherwise know nothing about it.
    @ObservationIgnored public var dropTrace: ((String) -> Void)?

    /// Holds an indicator on screen without the watchdog underneath it.
    ///
    /// Only for the screenshot harness, which freezes a drop indicator so its weight
    /// can be reviewed — a real drag cannot be held still for a camera, and the
    /// watchdog would quite correctly wipe a frozen one as stale.
    public func pinDropTargetForCapture(_ target: FolderDropTarget?) {
        folderDropTarget = target
    }

    public func setItemDropTarget(_ target: ItemDropTarget?) {
        dropHeartbeat = Date()
        if itemDropTarget != target { itemDropTarget = target }
        if target != nil { startDropWatchdog() }
    }

    /// Clears a stranded indicator.
    ///
    /// AppKit keeps sending dragging updates while a session is live, even with the
    /// pointer held still, so a stretch of silence means the drag is over and nobody
    /// told us — it was cancelled, or it landed on a view with a handler of its own.
    /// That is the grey line that used to stay on screen until the next drag.
    private func startDropWatchdog() {
        guard dropWatchdog == nil else { return }
        dropWatchdog = Task { @MainActor [weak self] in
            defer { self?.dropWatchdog = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let live = self else { return }
                guard live.folderDropTarget != nil || live.itemDropTarget != nil else { return }
                guard Date().timeIntervalSince(live.dropHeartbeat) > 0.4 else { continue }
                live.folderDropTarget = nil
                live.itemDropTarget = nil
                return
            }
        }
    }

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

    /// Folder rows the sidebar is showing collapsed. Lives here rather than in the
    /// view so the flattened row list can be cached against it.
    public var collapsedFolders: Set<UUID> = []

    @ObservationIgnored
    var folderRowCache: (revision: Int, collapsed: Set<UUID>, rows: [SidebarFolderRow])?
    @ObservationIgnored
    var sidebarCountCache: (revision: Int, counts: SidebarCounts)?
    @ObservationIgnored
    var folderPickerCache: (revision: Int, choices: [FolderChoice])?
    @ObservationIgnored
    var tagNameCache: (revision: Int, names: [String], counts: [String: Int])?

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
    public let accessibility: AccessibilityStatus

    /// How this platform says "summon" and "save what's selected", already rendered.
    ///
    /// Nil where there is no such gesture. The shortcut itself is a `HotKeyCombo`,
    /// which is Carbon to its core and lives in the macOS target; only the string
    /// crosses over, so an empty state can name the shortcut without this file
    /// knowing what a virtual key code is.
    public var summonShortcutLabel: String?
    public var quickSaveShortcutLabel: String?

    /// Held modifiers, on their own observable object so that watching them redraws
    /// the footer and nothing else. See `PanelModifierState`.
    public let modifiers = PanelModifierState()

    private var toastTask: Task<Void, Never>?
    private var autoLockTimer: Timer?

    public init(services: PlatformServices) throws {
        self.services = services
        let paths = LibraryPaths.standard()
        self.paths = paths
        let vault = Vault(paths: paths)
        self.vault = vault
        self.store = try LibraryStore(paths: paths, vault: vault)
        self.intelligence = Intelligence()
        self.accessibility = AccessibilityStatus(probe: services.hasAccessibility)
        self.settings = AppSettings()
        self.importer = Importer(store: store, intelligence: intelligence)

        applySettings()
        startAutoLockTimer()
        startLockOnAwayObservers()
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
        clipboard.isEnabled = settings.clipboardHistoryEnabled
        // Persistence is only meaningful while history is being kept at all: keeping a
        // file that nothing is allowed to add to is just an old log left lying around.
        clipboard.applyPersistence(settings.clipboardHistoryEnabled && settings.clipboardPersists)
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
                                           frontmostAppName: focus.previousAppName)
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

    /// Set when the library asks to delete something. The panel confirms inside its
    /// ⌘K overlay; a window has room for a real alert and should use one.
    public var pendingDeleteID: UUID?

    public var pendingDeleteTitle: String {
        pendingDeleteID.flatMap { id in store.snapshots.first { $0.id == id }?.title } ?? "this item"
    }

    public func requestDeleteSelected() {
        guard let id = mainSelection ?? actionTarget?.id else { return }
        pendingDeleteID = id
    }

    public func confirmPendingDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        deleteItem(id)
    }

    /// Routes a chord in the library window. Returns false to let the window have it.
    @discardableResult
    public func routeMainWindow(_ chord: KeyChord, columns: Int) -> Bool {
        switch (chord.key, chord.modifiers) {
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

    /// ⇥ needs somewhere to go: the selected item must sit in a folder, and we must
    /// not already be scoped to one.
    public var selectionHasFolder: Bool {
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
                    .map { FolderChoice(id: $0.id, label: $0.path.joined(separator: " › "),
                                symbolName: $0.symbolName) }
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
        let folder = folderID.flatMap { store.folder(id: $0) }
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
        secretEntry = ""
        secretError = nil
        // No store.refresh() here: every mutating method and both vault transitions
        // already refresh, so the snapshots are current. Refreshing again cost a full
        // fetch plus a decrypt of every sealed item before the window appeared.
        runSearch()
        isPanelVisible = true
        // Summoning the panel is the clearest signal of use there is. Without this,
        // `autoLockMinutes` measured from the unlock rather than from the last thing
        // you did, so an open vault relocked mid-session while you were using it.
        vault.noteActivity()
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
        vault.noteActivity()

        if snapshot.isLocked {
            mode = .unlock(pendingItemID: id)
            secretEntry = ""
            secretError = nil
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

    /// Set by the test harnesses. Delivery is *recorded* instead of performed: no
    /// pasteboard write, no synthesised ⌘V.
    ///
    /// The self-test used to exercise ⌘1–⌘9 by really activating an item, which wrote
    /// the clipboard and pasted into whatever app happened to be frontmost. It did
    /// that on someone's machine while they were writing an email. A harness must
    /// never reach outside the app.
    /// Defaults to true whenever *any* harness env var is set, so a new harness
    /// cannot forget to opt in. Belt and braces: the opt-in is also explicit in each
    /// harness, but the default is the one that matters.
    @ObservationIgnored public var isHarness = ProcessInfo.processInfo.environment.keys.contains {
        $0.hasPrefix("SUMMON_") && $0 != "SUMMON_DEMO" && $0 != "SUMMON_APPEARANCE"
    }
    @ObservationIgnored public private(set) var lastDelivery: (id: UUID, style: UseStyle)?

    private func deliver(_ id: UUID, style: UseStyle) {
        if isHarness {
            lastDelivery = (id, style)
            store.recordUse(id: id, inApp: focus.previousBundleID)
            dismissPanel()
            return
        }

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
            inserter.writeToPasteboard(payload, plainOnly: false)
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
        if services.hasAccessibility() || !settings.autoPaste {
            show(Toast(text: "Copied", symbol: "doc.on.clipboard", tone: .success,
                       detail: "Press ⌘V wherever you need it"))
        } else {
            show(Toast(text: "Copied — press ⌘V", symbol: "doc.on.clipboard", tone: .warning,
                       detail: "Allow Accessibility to have Summon paste for you"))
            // Ask once per launch, and only after it would have helped.
            if !accessibilityPromptShown {
                accessibilityPromptShown = true
                services.requestAccessibility()
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
        return DragProvider.make(for: payload, title: snapshot.title, itemID: id)
    }

    /// A drag that carries the row's identity but none of its contents.
    ///
    /// For a locked item, and for anything whose payload cannot be built. Refusing to
    /// drag at all was right while a drag could only ever leave the app — but filing
    /// something into a folder reveals nothing about it, and being unable to tidy a
    /// locked item without first unlocking it was a rule with no reason behind it.
    public func identityOnlyDragProvider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerSummonID(id, as: SummonDragType.item)
        return provider
    }

    // MARK: - Vault

    public func tryBiometricUnlock() async {
        guard vault.biometricsEnabled else { return }
        do {
            try await vault.unlockWithBiometrics()
            afterUnlock()
        } catch {
            // Silent: the entry field is already on screen as the fallback.
            Log.vault.info("Biometric unlock declined or failed.")
        }
    }

    /// Unlocks from the library, where there is no panel to put the field in.
    /// Returns false and leaves an explanation in `secretError` when it is wrong.
    @discardableResult
    public func unlockInPlace(secret: String) async -> Bool {
        do {
            try await vault.unlock(secret: secret)
            secretError = nil
            store.scrubSensitiveContent()
            store.refresh()
            runSearch()
            show(Toast(text: "Unlocked", symbol: "lock.open", tone: .success))
            resumeAfterUnlock()
            return true
        } catch {
            secretError = (error as? VaultError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public func submitSecret() {
        // Fire-and-forget from the field's `onComplete`, which cannot await. `isBusy`
        // is what stops a second submission landing while the first is still deriving.
        Task { await submitSecretAsync() }
    }

    public func submitSecretAsync() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await vault.unlock(secret: secretEntry)
            afterUnlock()
        } catch {
            secretError = (error as? VaultError)?.errorDescription ?? error.localizedDescription
            secretEntry = ""
        }
    }

    private func afterUnlock() {
        secretEntry = ""
        secretError = nil
        // The first open after an upgrade is the only chance to repair what earlier
        // versions left in the clear, because repairing it needs the key.
        store.scrubSensitiveContent()
        store.refresh()
        runSearch()
        if case .unlock(let pending) = mode {
            mode = .search
            if let pending { use(pending) }
        } else {
            mode = .search
        }
        resumeAfterUnlock()
    }

    /// Runs whatever was waiting on a key — the same continuation the PIN sheet uses,
    /// so unlocking an existing vault finishes the interrupted action too.
    private func resumeAfterUnlock() {
        let resume = afterUnlockAction
        afterUnlockAction = nil
        resume?()
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

    /// Locks when the Mac stops being in front of the person using it.
    ///
    /// The idle timer alone did not cover this. It stops running while the machine is
    /// asleep, so closing the lid a minute after unlocking left the master key in
    /// memory until the next tick after waking. Sleeping and locking the screen are
    /// both unambiguous "I have walked away", so they lock outright rather than
    /// starting a countdown — and the README already claimed the key was discarded on
    /// sleep, which until now it was not.
    private func startLockOnAwayObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockIfUnlocked() }
            }
        }

        // Screen lock has no NSWorkspace notification; it is a distributed one.
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockIfUnlocked() }
        }
    }

    /// Locks without a toast: nobody is looking at the screen when this fires.
    private func lockIfUnlocked() {
        guard vault.isUnlocked else { return }
        vault.lock()
        FileStore.clearScratch()
        ThumbnailCache.shared.invalidateAll()
        store.refresh()
        runSearch()
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
        // Handed the action to retry, so setting a PIN finishes what you asked for
        // rather than leaving you to go and ask again.
        let label = item.title.isEmpty ? "this item" : "\u{201C}\(item.title)\u{201D}"
        guard requireUnlockedVault(
            reason: sensitive ? "to encrypt \(label)." : "to decrypt \(label).",
            thenRetry: { [weak self] in self?.setItemSensitive(id, sensitive) }
        ) else { return }
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
        let folderID = folder.id
        let name = "\u{201C}\(folder.name)\u{201D}"
        guard requireUnlockedVault(
            reason: sensitive ? "to encrypt the folder \(name)." : "to decrypt the folder \(name).",
            thenRetry: { [weak self] in
                guard let self, let again = store.folder(id: folderID) else { return }
                setFolderSensitive(again, sensitive)
            }
        ) else { return }
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
    ///
    /// `thenRetry` is run once the vault is open, so the action that triggered all
    /// this actually happens. Without it, marking an item sensitive with no PIN set
    /// asked for a PIN, got one, and then did nothing — the request had been recorded
    /// in a flag that nothing read.
    /// - Parameter reason: finishes the sentence "Enter your PIN…", so the prompt
    ///   names the thing that was asked for. It used to summon the whole panel over
    ///   the library to announce that everything was about to be unlocked, when all
    ///   anyone had done was flick one switch.
    @discardableResult
    public func requireUnlockedVault(reason: String,
                                     thenRetry retry: (() -> Void)? = nil) -> Bool {
        if vault.isUnlocked { return true }
        afterUnlockAction = retry

        if !vault.isConfigured {
            // No key exists yet, so there is nothing to unlock — the question is what
            // the PIN should be.
            presentLockSheet(.create)
            return false
        }

        // Asked where you already are. The panel has its own unlock pane and is the
        // right place when you are in it; anywhere else, the window asks.
        if isPanelVisible {
            mode = .unlock(pendingItemID: nil)
        } else {
            presentLockSheet(.unlock(reason: reason))
        }
        return false
    }

    /// Which PIN question the library window is asking, if any.
    public private(set) var lockSheet: LockSheet.Purpose?

    /// What to run once there is a key. Not observed: it is a continuation, not state
    /// anything on screen depends on.
    @ObservationIgnored private var afterUnlockAction: (() -> Void)?

    public func beginPINSetup(thenRetry retry: (() -> Void)? = nil) {
        afterUnlockAction = retry
        presentLockSheet(.create)
    }

    /// Brings the library forward and asks there. The panel is a transient surface
    /// that closes the moment you look away, which is the wrong place to be typing a
    /// PIN — and a panel arriving unbidden over the window you are working in is
    /// startling regardless of what it wants.
    private func presentLockSheet(_ purpose: LockSheet.Purpose) {
        dismissPanel()
        showMainWindowHandler?()
        lockSheet = purpose
    }

    /// Closes the sheet without discarding a pending action — the action has either
    /// already run or is about to.
    public func finishLockSheet() {
        lockSheet = nil
    }

    /// Opens the turn-off flow on the library window. Settings drives its own copy;
    /// this exists so the screenshot harness can hold the sheet open for review.
    public func beginTurnOffPINForCapture() {
        lockSheet = .turnOff
    }

    public func cancelLockSheet() {
        lockSheet = nil
        afterUnlockAction = nil
    }

    /// A plain-English count of what the PIN is protecting, for the confirmation that
    /// turning it off will decrypt all of it.
    public var encryptedContentSummary: String {
        let items = store.snapshots.count(where: \.isSensitive)
        guard items > 0 else {
            return "Nothing is encrypted right now, so nothing on disk changes."
        }
        return items == 1
            ? "The 1 encrypted item will be decrypted back to plain text on disk."
            : "All \(items) encrypted items will be decrypted back to plain text on disk."
    }

    /// Checks a PIN without changing the lock state, for the "current PIN" step.
    ///
    /// Deliberately routed through the vault's own attempt counter: this is a guess
    /// like any other, and a verification path that skipped the cooldown would be a
    /// way around it.
    public func verifySecret(_ secret: String) async -> Bool {
        let wasLocked = !vault.isUnlocked
        do {
            try await vault.unlock(secret: secret)
            if wasLocked { vault.lock() }
            secretError = nil
            return true
        } catch {
            secretError = (error as? VaultError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Re-keys the vault. Content stays encrypted throughout — the master key is
    /// unwrapped with the old secret and re-wrapped with the new one, so nothing is
    /// decrypted and rewritten.
    ///
    /// Switching between a PIN and a passphrase is the same operation, which is why
    /// there is no separate "convert" path to get wrong.
    public func changeSecret(
        current: String,
        new: String,
        kind: VaultSecretKind,
        onError: (String) -> Void
    ) async {
        let wasKind = vault.secretKind
        do {
            try await vault.changeSecret(current: current, new: new, kind: kind)
        } catch {
            onError((error as? VaultError)?.errorDescription ?? error.localizedDescription)
            return
        }
        store.refresh()
        show(Toast(
            text: kind == wasKind ? "\(kind.displayName) changed" : "Now using a \(kind.noun)",
            symbol: "lock.rotation",
            tone: .success
        ))
    }

    /// Turns protection off: everything sensitive is decrypted back to plaintext
    /// first, because a key file removed with content still sealed would leave that
    /// content unreadable forever.
    ///
    /// Returns the number of items it decrypted, or nil if it could not proceed.
    @discardableResult
    public func removeVaultProtection() -> Int? {
        guard vault.isUnlocked else {
            show(Toast(text: "Unlock first", symbol: "lock", tone: .warning))
            return nil
        }
        do {
            let count = try store.clearAllSensitivity()
            try vault.removePIN()
            store.refresh()
            runSearch()
            show(Toast(text: count == 0 ? "Lock removed" : "Lock removed — \(count) items decrypted",
                       symbol: "lock.open", tone: .success))
            return count
        } catch {
            show(Toast(text: "Couldn’t remove the lock", symbol: "exclamationmark.triangle",
                       tone: .danger, detail: error.localizedDescription))
            return nil
        }
    }

    /// The Settings button. Deliberately the same call as everywhere else.
    ///
    /// This used to be its own three lines, which drifted: it dropped the key but left
    /// the decrypted scratch copies on disk and the decoded thumbnails in memory. The
    /// one lock a person asks for explicitly was the one that protected least.
    public func lockVaultNow() {
        lockVault()
    }


    /// Sets the secret and resumes whatever was interrupted. Reports back rather than
    /// throwing, so the sheet can show the reason next to the field.
    public func completeSecretSetup(
        secret: String,
        kind: VaultSecretKind = .pin,
        onError: (String) -> Void
    ) async {
        do {
            try await vault.setUpSecret(secret, kind: kind)
        } catch {
            onError((error as? VaultError)?.errorDescription ?? error.localizedDescription)
            return
        }
        lockSheet = nil
        store.scrubSensitiveContent()
        store.refresh()
        runSearch()
        show(Toast(text: "\(kind.displayName) set", symbol: "lock.fill", tone: .success,
                   detail: "Sensitive items are encrypted with it."))
        let resume = afterUnlockAction
        afterUnlockAction = nil
        resume?()
    }

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
            let selection = await services.captureSelection()
            let created = await importer.importSelection(selection)
            runSearch()
            if created.isEmpty {
                show(Toast(text: "Nothing selected to save", symbol: "questionmark.circle", tone: .warning,
                           detail: quickSaveShortcutLabel.map { "Select text or files, then press \($0)" }))
            } else if created.count == 1 {
                show(Toast(text: "Saved “\(created[0].title)”", symbol: "sparkles", tone: .success))
            } else {
                show(Toast(text: "Saved \(created.count) items", symbol: "sparkles", tone: .success))
            }
        }
    }

    public func saveClipboardEntry(_ entry: ClipboardEntry) {
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

    /// Every tag in the library, for completion in the tag field, with how many items
    /// carry each — which is what separates a tag you use constantly from a typo you
    /// made once.
    public var knownTagNames: [String] { knownTags.names }
    public var knownTagCounts: [String: Int] { knownTags.counts }

    private var knownTags: (names: [String], counts: [String: Int]) {
        if let cache = tagNameCache, cache.revision == store.revision {
            return (cache.names, cache.counts)
        }
        let tags = store.allTags()
        let names = tags.map(\.name).sorted()
        let counts = Dictionary(tags.map { ($0.name, ($0.items ?? []).count) },
                                uniquingKeysWith: { first, _ in first })
        tagNameCache = (store.revision, names, counts)
        return (names, counts)
    }

    /// The folder tree as flat "Clients › Acme" labels, for a menu picker.
    ///
    /// Sorted by path so the tree still reads as a tree in a flat list, and cached
    /// with the library so a picker in a view body is not a fetch per render.
    public var folderChoicesForPicker: [FolderChoice] {
        if let cache = folderPickerCache, cache.revision == store.revision { return cache.choices }
        let choices = store.allFolders()
            .sorted {
                $0.path.joined(separator: "\u{1F}")
                    .localizedStandardCompare($1.path.joined(separator: "\u{1F}")) == .orderedAscending
            }
            .map { FolderChoice(id: $0.id, label: $0.path.joined(separator: " › "),
                                symbolName: $0.symbolName) }
        folderPickerCache = (store.revision, choices)
        return choices
    }

    /// Seeds the tag field with a half-typed tag so the screenshot harness can catch
    /// its suggestion menu open. Nil in normal use.
    public var tagDraftForCapture: String?

    // MARK: - Tag actions

    /// Renames a tag everywhere it is used. A name that already exists merges into it
    /// rather than leaving two identical-looking rows in the sidebar.
    public func renameTag(_ tag: SummonTag, to name: String) {
        let before = tag.name
        guard store.renameTag(tag, to: name) else { return }
        // The selection follows the rename, or the sidebar would be showing a filter
        // for a name that no longer exists.
        if sidebarSelection == .tag(before) {
            sidebarSelection = .tag(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        runSearch()
    }

    public func deleteTag(_ tag: SummonTag) {
        let name = tag.name
        let affected = (tag.items ?? []).count
        store.deleteTag(tag)
        if sidebarSelection == .tag(name) { sidebarSelection = .all }
        runSearch()
        show(Toast(text: "Removed #\(name)", symbol: "tag.slash", tone: .neutral,
                   detail: affected == 1 ? "From 1 item" : "From \(affected) items"))
    }

    // MARK: - Filing actions

    /// Moves an item into a folder, or out of every folder when `folder` is nil.
    ///
    /// This is what a drag onto a folder row has always looked like it would do and
    /// never did: the row's drag vended its contents, so the sidebar saw a stray file
    /// or a piece of text and either re-imported it as a duplicate or ignored it.
    public func fileItem(_ id: UUID, into folder: SummonFolder?) {
        guard let item = store.item(id: id) else { return }
        guard item.folder?.id != folder?.id else { return }

        // Moving into a sensitive folder has to re-encrypt the bytes, which cannot be
        // done while the vault is shut.
        let becomesSensitive = folder?.isEffectivelySensitive ?? false
        if (becomesSensitive || item.isEffectivelySensitive) && !vault.isUnlocked && vault.isConfigured {
            show(Toast(text: "Unlock to move this", symbol: "lock", tone: .warning))
            return
        }

        let title = item.title.isEmpty ? "Item" : item.title
        store.move(item, to: folder)
        runSearch()
        show(Toast(text: folder.map { "Moved “\(title)” to \($0.name)" } ?? "Moved “\(title)” out of its folder",
                   symbol: folder?.symbolName ?? "tray", tone: .success))
    }

    public func fileItem(_ id: UUID, intoFolderID folderID: UUID?) {
        fileItem(id, into: folderID.flatMap { store.folder(id: $0) })
    }

    /// Drops an item into place beside another one, within the folder they share.
    public func reorderItem(_ id: UUID, relativeTo siblingID: UUID, placeAfter: Bool) {
        guard id != siblingID,
              let item = store.item(id: id),
              let sibling = store.item(id: siblingID)
        else { return }
        store.reorderItem(item, relativeTo: sibling, placeAfter: placeAfter)
        runSearch()
    }

    /// Text dropped in from another app, as a snippet in `folder`.
    public func acceptDroppedText(_ text: String, into folder: SummonFolder?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = store.createSnippet(title: Heuristics.title(forText: trimmed),
                                       body: trimmed, folder: folder)
        runSearch()
        show(Toast(text: "Added \u{201C}\(item.title)\u{201D}",
                   symbol: "text.quote", tone: .success))
    }

    /// Anything dragged in from outside Summon, filed into `folder`.
    ///
    /// Text used to be accepted by a folder row and then silently discarded — the
    /// drop reported success and nothing appeared. Dropping a paragraph on a folder
    /// now makes a snippet in it, which is what dropping a file already did.
    public func acceptForeignDrop(_ info: DropInfo, into folder: SummonFolder?) {
        if info.hasItemsConforming(to: [.fileURL]) {
            let providers = info.itemProviders(for: [.fileURL])
            Task { @MainActor in
                let urls = await FolderDropDelegate.urls(from: providers)
                guard !urls.isEmpty else { return }
                importDroppedFiles(urls, into: folder)
            }
            return
        }
        let providers = info.itemProviders(for: [.text])
        Task { @MainActor in
            guard let text = await FolderDropDelegate.text(from: providers) else { return }
            acceptDroppedText(text, into: folder)
        }
    }

    // MARK: - Creation actions


    /// The id of a folder whose name is being typed in the sidebar, and of an item
    /// whose title is being typed in the detail pane. Nothing is modal: the thing
    /// exists as soon as you ask for it, and you edit it in place.
    public var renamingFolderID: UUID?
    public var renamingTagID: UUID?
    public var focusNewItemTitle = false

    public func beginNewSnippet() {
        showMainWindowHandler?()
        let folder: SummonFolder? = {
            guard case .folder(let id) = sidebarSelection else { return nil }
            return store.folder(id: id)
        }()
        // Created empty and selected, rather than assembled behind a Cancel button.
        // An untitled snippet with no body is removed again when you leave it.
        let item = store.createSnippet(title: "", body: "", folder: folder)
        store.refresh()

        // Show it where it actually landed. Creating from Pinned, a tag or a type
        // filter made an item the current section could never display, so it looked
        // like nothing had happened — the snippet was real, just filtered out.
        if !sectionShows(item.id) {
            sidebarSelection = folder.map { .folder($0.id) } ?? .all
        }
        runSearch()
        mainSelection = item.id
        focusNewItemTitle = true
    }

    /// Would the current sidebar section display this item?
    private func sectionShows(_ id: UUID) -> Bool {
        itemsForSidebar().contains { $0.id == id }
    }

    /// Where a new item would go, for the menu to say so out loud.
    public var newItemDestination: String {
        guard case .folder(let id) = sidebarSelection,
              let folder = store.folder(id: id)
        else { return "All Items" }
        return folder.name
    }

    /// Drops a snippet that was created and then left completely empty, so abandoning
    /// a new item does not litter the library with blanks.
    public func discardIfEmpty(_ id: UUID) {
        guard let item = store.item(id: id), item.kind.isTextual else { return }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (store.resolveBodyText(item, key: vault.currentKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty || title == "Untitled", body.isEmpty else { return }
        store.delete(item)
        if mainSelection == id { mainSelection = nil }
        runSearch()
    }

    public func beginNewFolder() {
        showMainWindowHandler?()
        let parent: SummonFolder? = {
            guard case .folder(let id) = sidebarSelection else { return nil }
            return store.folder(id: id)
        }()
        let folder = store.createFolder(name: "New Folder", parent: parent)
        sidebarSelection = .folder(folder.id)
        renamingFolderID = folder.id
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
            // This folder's own items, not its whole subtree. A parent used to absorb
            // everything nested under it, so an item you had deliberately filed two
            // levels down turned up in three different places.
            items = items.filter { $0.folderID == id }
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
        // A folder is the one place with a hand-made order to respect. Elsewhere —
        // and while searching — the view has an ordering rule of its own.
        if case .folder = sidebarSelection {
            return items.sorted {
                $0.sortIndex == $1.sortIndex ? $0.updatedAt > $1.updatedAt
                                             : $0.sortIndex < $1.sortIndex
            }
        }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    public var sidebarTitle: String {
        switch sidebarSelection {
        case .all: "All Items"
        case .recents: "Recents"
        case .pinned: "Pinned"
        case .locked: "Sensitive"
        case .clipboard: "Clipboard"
        case .folder(let id): store.folder(id: id)?.name ?? "Folder"
        case .tag(let name): "#\(name)"
        case .kind(let kind): kind.pluralName
        }
    }
}
