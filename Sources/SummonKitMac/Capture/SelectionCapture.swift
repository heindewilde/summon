import AppKit
import Foundation
import SummonKit

/// Grabs whatever is selected right now, wherever you are.
///
/// In Finder that means the selected files, read over Apple Events. Everywhere else
/// it synthesises ⌘C and reads the pasteboard back, restoring the previous contents
/// so the hotkey does not quietly destroy what you had copied.
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
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier == "com.apple.finder" {
            let files = SelectionCapture.finderSelection()
            if !files.isEmpty { return .files(files) }
        }
        return await captureViaCopy()
    }

    /// Reads the Finder selection without needing Accessibility.
    public static func finderSelection() -> [URL] {
        let source = """
        tell application "Finder"
            set theSelection to selection as alias list
            set output to ""
            repeat with anItem in theSelection
                set output to output & POSIX path of (anItem as text) & linefeed
            end repeat
            return output
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let result = script.executeAndReturnError(&error)
        if let error {
            Log.capture.warning("Finder selection unavailable: \(String(describing: error), privacy: .public)")
            return []
        }
        return (result.stringValue ?? "")
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
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
