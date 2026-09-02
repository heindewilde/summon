import AppKit
import Foundation

/// What the save-selection hotkey managed to grab.
public enum CapturedSelection: Sendable {
    case files([URL])
    case text(String, rtf: Data?)
    case image(Data)
    case nothing
}

/// Grabs whatever is selected right now, wherever you are.
///
/// In Finder that means the selected files, read over Apple Events. Everywhere else
/// it synthesises ⌘C and reads the pasteboard back, restoring the previous contents
/// so the hotkey does not quietly destroy what you had copied.
@MainActor
public struct SelectionCapture {
    private let inserter: Inserter

    public init(inserter: Inserter) { self.inserter = inserter }

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
        defer { SelectionCapture.restorePasteboard(pb, from: saved) }

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
    static func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboard.PasteboardType: Data] {
        var saved: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pb.types ?? [] {
            if let data = pb.data(forType: type) { saved[type] = data }
        }
        return saved
    }

    static func restorePasteboard(_ pb: NSPasteboard, from saved: [NSPasteboard.PasteboardType: Data]) {
        guard !saved.isEmpty else { return }
        pb.clearContents()
        pb.declareTypes(Array(saved.keys), owner: nil)
        for (type, data) in saved { pb.setData(data, forType: type) }
    }
}
