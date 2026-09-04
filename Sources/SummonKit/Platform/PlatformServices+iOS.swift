#if canImport(UIKit) && !os(macOS)
import Foundation
import UIKit
import UniformTypeIdentifiers

/// What a phone can do, which is less than a Mac and honest about it.
///
/// The protocols were drawn around what `AppModel` asks for, so most of this is a
/// truthful "no" rather than a stub pretending otherwise. `InsertOutcome.copiedOnly`
/// already existed as the answer for a Mac without an Accessibility grant, and it is
/// the only answer iOS has: no app may paste into another.
@MainActor
final class UIKitInsertion: InsertionService {
    func currentClipboardText() -> String {
        UIPasteboard.general.string ?? ""
    }

    /// One `setItems` call, mirroring the Mac's single `writeObjects`: the pasteboard
    /// is cleared by the assignment, so writing representation by representation would
    /// leave each one erasing the last.
    func writeToPasteboard(_ payload: InsertPayload, plainOnly: Bool) {
        var item: [String: Any] = [:]

        if let rtf = payload.rtf, !plainOnly {
            item[UTType.rtf.identifier] = rtf
        }
        if let text = payload.plainText {
            item[UTType.utf8PlainText.identifier] = Data(text.utf8)
        }
        if let data = payload.imageData {
            item[UTType.png.identifier] = data
        }
        if let url = payload.fileURL {
            item[UTType.fileURL.identifier] = url as NSURL
        }

        UIPasteboard.general.items = item.isEmpty ? [] : [item]
    }

    func insert(_ payload: InsertPayload, into focus: any FocusService,
                plainOnly: Bool, autoPaste: Bool) async -> InsertOutcome {
        guard !payload.isEmpty else { return .failed("Nothing to insert.") }
        writeToPasteboard(payload, plainOnly: plainOnly)
        // Not a degraded path here — it is the only path. iOS gives no app the ability
        // to type into another, so "copied, now paste it" is the whole interaction.
        return .copiedOnly
    }
}

/// There is no "the app you were just in" on iOS.
///
/// Reporting nothing is the correct answer rather than a gap: `SearchIndex` already
/// treats a nil bundle id as "no app affinity" and falls back to pinned and recent,
/// which is exactly what a phone should show.
@MainActor
final class NoFocus: FocusService {
    var previousBundleID: String? { nil }
    var previousAppName: String? { nil }
    func capture() {}
    func clear() {}
    func restoreFocus() -> Bool { false }
}

/// iOS has no background pasteboard watching, and pretending otherwise would mean a
/// permission prompt on every launch for a tray that could never fill itself.
@MainActor
final class NoClipboardHistory: ClipboardService {
    var isEnabled: Bool = false
    var maxEntries: Int = 0
    var entries: [ClipboardEntry] { [] }
    func applyPersistence(_ enabled: Bool) {}
    func start() {}
    func stop() {}
    func ignoreNextChange() {}
    func clear() {}
    func remove(_ id: UUID) {}
}

extension PlatformServices {
    /// Everything a phone can do, wired together.
    @MainActor
    public static func iOS() -> PlatformServices {
        PlatformServices(
            focus: NoFocus(),
            insertion: UIKitInsertion(),
            clipboard: NoClipboardHistory(),
            // There is no such permission to grant, and a warning that can never be
            // resolved is worse than no warning.
            hasAccessibility: { true })
    }
}
#endif
