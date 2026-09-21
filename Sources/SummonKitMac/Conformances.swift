import AppKit
import SummonKit

/// The macOS answers to `PlatformServices`.
///
/// Written as explicit witnesses rather than by declaring conformance on the types
/// themselves, because the concrete methods carry default arguments — `plainOnly` and
/// `to pb: NSPasteboard = .general` — and a defaulted parameter does not satisfy a
/// protocol requirement. Spelling them out is also where the platform-shaped members
/// stay behind: `copyCurrentSelection()` returns an `NSPasteboard.PasteboardType`, so
/// it cannot be in a protocol iOS conforms to, and its one caller is here anyway.
extension FocusTracker: FocusService {
    public var previousAppName: String? { previousApp?.localizedName }
}

extension Inserter: InsertionService {
    public func writeToPasteboard(_ payload: InsertPayload, plainOnly: Bool) {
        writeToPasteboard(payload, plainOnly: plainOnly, to: .general)
    }

    public func insert(_ payload: InsertPayload,
                       into focus: any FocusService,
                       plainOnly: Bool,
                       autoPaste: Bool) async -> InsertOutcome {
        guard let tracker = focus as? FocusTracker else { return .failed("No focus tracker.") }
        return await insert(payload, into: tracker, plainOnly: plainOnly, autoPaste: autoPaste)
    }
}

extension ClipboardMonitor: ClipboardService {
    public var isSupported: Bool { true }
}

extension PlatformServices {
    /// Everything the Mac can do, wired together.
    ///
    /// Resolves its own `LibraryPaths` rather than taking one. `standard()` is
    /// idempotent — it returns the same root and creates the directories if they are
    /// missing — so both this and `AppModel` calling it is a repetition, not a
    /// disagreement.
    @MainActor
    public static func macOS() -> PlatformServices {
        let paths = LibraryPaths.standard()
        let focus = FocusTracker()
        let inserter = Inserter()
        let clipboard = ClipboardMonitor(paths: paths)
        return PlatformServices(
            focus: focus,
            insertion: inserter,
            clipboard: clipboard,
            hasAccessibility: { Inserter.hasAccessibility },
            requestAccessibility: { Inserter.requestAccessibility() },
            captureSelection: {
                await SelectionCapture(inserter: inserter) { clipboard.ignoreNextChange() }.capture()
            })
    }
}
