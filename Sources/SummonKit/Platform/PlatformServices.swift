import Foundation

/// What the app needs from the machine it is running on.
///
/// `AppModel` used to construct an `Inserter`, a `FocusTracker` and a
/// `ClipboardMonitor` in its initialiser, which meant the controller for the whole
/// app named three AppKit-backed types and could only ever run on a Mac. These
/// protocols are the seam. The window layer already talked to `AppModel` through
/// optional closures; this is the same idea pointed downwards.
///
/// The shapes are drawn around what `AppModel` actually asks for, not around what the
/// macOS classes happen to offer. `Inserter.copyCurrentSelection()` returns an
/// `NSPasteboard.PasteboardType` and so cannot be in a protocol that iOS conforms to;
/// it stays on the concrete type, where its one caller lives.

/// The result of trying to put something where the caret was.
public enum InsertOutcome: Sendable, Equatable {
    /// Written to the clipboard and pasted for you.
    case pasted
    /// Written to the clipboard; you press the paste key yourself. Not a failure —
    /// it is the honest outcome without an Accessibility grant, and on a platform
    /// where no app may paste into another it is the only outcome there is.
    case copiedOnly
    case failed(String)
}

/// Where the caret was before Summon took focus.
///
/// Meaningful only where an app can be "the one you were just in". Conformances
/// elsewhere report nothing and restore nothing, which reads correctly through the
/// ranking layer: `SearchIndex` already treats a nil bundle ID as "no app affinity"
/// and falls back to pinned and recent.
@MainActor
public protocol FocusService: AnyObject {
    var previousBundleID: String? { get }
    var previousAppName: String? { get }
    func capture()
    func clear()
    @discardableResult func restoreFocus() -> Bool
}

/// Getting a chosen item to where it is wanted.
@MainActor
public protocol InsertionService: AnyObject {
    func currentClipboardText() -> String
    func writeToPasteboard(_ payload: InsertPayload, plainOnly: Bool)
    @discardableResult
    func insert(_ payload: InsertPayload,
                into focus: any FocusService,
                plainOnly: Bool,
                autoPaste: Bool) async -> InsertOutcome
}

/// The recent-clipboard tray.
///
/// `ignoreNextChange()` is the one that has to exist everywhere, even where nothing
/// is watching: Summon writes to the clipboard itself on every insert, and without
/// it the tray fills up with things it just put there.
@MainActor
public protocol ClipboardService: AnyObject {
    /// Whether this platform has a clipboard history at all.
    ///
    /// Distinct from `isEnabled`, which is a preference: the Mac's tray can be switched
    /// off and still be a thing that exists. iOS cannot watch the pasteboard in the
    /// background, so the answer there is no, and the sidebar should not offer a
    /// section that can never fill.
    var isSupported: Bool { get }
    var isEnabled: Bool { get set }
    var maxEntries: Int { get set }
    var entries: [ClipboardEntry] { get }
    func applyPersistence(_ enabled: Bool)
    func start()
    func stop()
    func ignoreNextChange()
    func clear()
    func remove(_ id: UUID)
}

/// The three of them, handed to `AppModel` at construction.
@MainActor
public struct PlatformServices {
    public var focus: any FocusService
    public var insertion: any InsertionService
    public var clipboard: any ClipboardService
    /// Whether this app may drive another one. Answered `true` where there is no such
    /// permission to grant, because a warning that can never be resolved is worse
    /// than no warning.
    public var hasAccessibility: @MainActor () -> Bool

    /// Asks for that permission. A no-op where it does not exist.
    public var requestAccessibility: @MainActor () -> Void

    /// Whatever is selected in the frontmost app right now — the ⌥⇧S path.
    ///
    /// A closure rather than a protocol because there is exactly one question to ask,
    /// and because how it is answered differs so completely: macOS reads the Finder
    /// selection over Apple Events, or copies and puts the clipboard back. A phone
    /// has no frontmost app to ask, and answers with nothing.
    public var captureSelection: @MainActor () async -> CapturedSelection

    public init(focus: any FocusService,
                insertion: any InsertionService,
                clipboard: any ClipboardService,
                hasAccessibility: @escaping @MainActor () -> Bool,
                requestAccessibility: @escaping @MainActor () -> Void = {},
                captureSelection: @escaping @MainActor () async -> CapturedSelection = { .nothing }) {
        self.focus = focus
        self.insertion = insertion
        self.clipboard = clipboard
        self.hasAccessibility = hasAccessibility
        self.requestAccessibility = requestAccessibility
        self.captureSelection = captureSelection
    }
}
