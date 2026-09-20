import AppKit
import Foundation
import SummonKit

/// Grabs whatever is selected right now, wherever you are.
///
/// Synthesises ⌘C and reads the pasteboard back, restoring the previous contents so
/// the hotkey does not quietly destroy what you had copied.
///
/// Finder used to be special-cased: its selection was read over Apple Events, which
/// needed a temporary exception the App Store does not allow (docs/sandbox-spike.md).
/// Files now come in through the Services menu, Finder's Quick Actions, and drag and
/// drop — all of which hand over the files rather than asking for them.
@MainActor
public struct SelectionCapture {
    private let inserter: Inserter
    /// Called immediately before the user's own clipboard is put back.
    ///
    /// Restoring writes to the pasteboard, which bumps `changeCount` and so looks to
    /// the clipboard monitor exactly like a fresh copy. Without this, a password that
    /// was correctly skipped on the way in came back around as a new history entry
    /// attributed to whatever app happened to be frontmost.
    private let willRestore: @MainActor () -> Void

    public init(inserter: Inserter, willRestore: @MainActor @escaping () -> Void = {}) {
        self.inserter = inserter
        self.willRestore = willRestore
    }

    public func capture() async -> CapturedSelection {
        await captureViaCopy()
    }

    private func captureViaCopy() async -> CapturedSelection {
        let pb = NSPasteboard.general
        let saved = SelectionCapture.snapshotPasteboard(pb)
        defer {
            willRestore()
            SelectionCapture.restorePasteboard(pb, from: saved)
        }

        guard let type = await inserter.copyCurrentSelection() else { return .nothing }

        switch type {
        case .png, .tiff:
            guard let data = pb.data(forType: type) else { return .nothing }
            return .image(data)
        case .rtf:
            let rtf = pb.data(forType: .rtf)
            return .text(pb.string(forType: .string) ?? "", rtf: rtf)
        default:
            guard let text = pb.string(forType: .string), !text.isEmpty else { return .nothing }
            return .text(text, rtf: nil)
        }
    }

    /// Preserves the user's clipboard across our synthetic ⌘C.
    ///
    /// Types are kept in order and *with* their data optional, because the markers
    /// that matter most here carry none. `org.nspasteboard.ConcealedType` is a
    /// zero-length flag meaning "this is a secret"; a dictionary keyed on types with
    /// data dropped it on the floor, so the clipboard came back from a save-selection
    /// stripped of the one thing telling every clipboard manager to ignore it.
    static func snapshotPasteboard(_ pb: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data?)] {
        (pb.types ?? []).map { ($0, pb.data(forType: $0)) }
    }

    static func restorePasteboard(_ pb: NSPasteboard, from saved: [(NSPasteboard.PasteboardType, Data?)]) {
        guard !saved.isEmpty else { return }
        pb.clearContents()
        // Declared whether or not there are bytes to follow, so marker types survive.
        pb.declareTypes(saved.map(\.0), owner: nil)
        for (type, data) in saved {
            if let data { pb.setData(data, forType: type) }
        }
    }
}
