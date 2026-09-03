import AppKit
import Foundation
import Testing
@testable import SummonKit

/// Mirrors `ClipboardMonitor.StoredEntry`, so the tests can lay down a real history
/// file without driving the monitor against the machine's actual clipboard.
private struct StoredEntryFixture: Codable {
    var id: UUID
    var capturedAt: Date
    var text: String
    var sourceBundleID: String?
    var sourceAppName: String?
}

@Suite("Clipboard history persistence")
@MainActor
struct ClipboardHistoryTests {

    private func writeHistory(_ texts: [String], in paths: LibraryPaths) throws {
        let stored = texts.map {
            StoredEntryFixture(id: UUID(), capturedAt: Date(), text: $0,
                               sourceBundleID: "com.example.app", sourceAppName: "Example")
        }
        try JSONEncoder().encode(stored)
            .write(to: paths.root.appending(path: "clipboard.json"))
    }

    private func historyExists(in paths: LibraryPaths) -> Bool {
        FileManager.default.fileExists(atPath: paths.root.appending(path: "clipboard.json").path)
    }

    @Test("With persistence on, an existing history is loaded")
    func loadsWhenPersistenceIsOn() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        try writeHistory(["an earlier copy"], in: paths)

        let monitor = ClipboardMonitor(paths: paths)
        monitor.applyPersistence(true)
        #expect(monitor.entries.count == 1)
        #expect(monitor.entries.first?.text == "an earlier copy")
    }

    /// The bug this exists for: history used to be read in `init`, before any setting
    /// had been applied, so it came back at every launch regardless of the toggle.
    @Test("Constructing the monitor reads nothing on its own")
    func initReadsNothing() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        try writeHistory(["a password, probably"], in: paths)

        let monitor = ClipboardMonitor(paths: paths)
        #expect(monitor.entries.isEmpty)
    }

    @Test("With persistence off, the history is not loaded and the file is deleted")
    func offMeansGone() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        try writeHistory(["a password, probably"], in: paths)
        #expect(historyExists(in: paths))

        let monitor = ClipboardMonitor(paths: paths)
        monitor.applyPersistence(false)
        #expect(monitor.entries.isEmpty)
        // "Off" has to mean the log is gone, not merely that nothing is added to it.
        #expect(!historyExists(in: paths))
    }

    @Test("Turning persistence off after it was on removes what it wrote")
    func turningOffRemovesTheFile() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        try writeHistory(["an earlier copy"], in: paths)

        let monitor = ClipboardMonitor(paths: paths)
        monitor.applyPersistence(true)
        #expect(historyExists(in: paths))

        monitor.applyPersistence(false)
        #expect(!historyExists(in: paths))
        #expect(!monitor.persistBetweenLaunches)
    }
}

@Suite("Pasteboard round-trip")
@MainActor
struct PasteboardRestoreTests {
    /// A private, named pasteboard, so the suite never touches the real one.
    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.heindewilde.summon.tests.\(UUID().uuidString)"))
    }

    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// The marker password managers set is a zero-length flag. Losing it across a
    /// save-selection meant the restored clipboard no longer said "this is a secret",
    /// so the very next poll recorded the password into history.
    @Test("A concealed marker survives being snapshotted and restored")
    func concealedMarkerSurvives() throws {
        let pb = scratchPasteboard()
        pb.declareTypes([concealed, .string], owner: nil)
        pb.setString("hunter2", forType: .string)

        let saved = SelectionCapture.snapshotPasteboard(pb)

        // Something else takes the clipboard, the way our synthetic ⌘C does.
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString("a copied selection", forType: .string)
        #expect(pb.types?.contains(concealed) != true)

        SelectionCapture.restorePasteboard(pb, from: saved)
        #expect(pb.types?.contains(concealed) == true)
        #expect(pb.string(forType: .string) == "hunter2")
    }

    @Test("Ordinary contents round-trip unchanged")
    func contentsRoundTrip() throws {
        let pb = scratchPasteboard()
        pb.declareTypes([.string, .rtf], owner: nil)
        pb.setString("plain", forType: .string)
        pb.setData(Data("{\\rtf1 rich}".utf8), forType: .rtf)

        let saved = SelectionCapture.snapshotPasteboard(pb)
        pb.clearContents()
        SelectionCapture.restorePasteboard(pb, from: saved)

        #expect(pb.string(forType: .string) == "plain")
        #expect(pb.data(forType: .rtf) == Data("{\\rtf1 rich}".utf8))
    }

    @Test("An empty pasteboard restores to an empty pasteboard")
    func emptyIsLeftAlone() throws {
        let pb = scratchPasteboard()
        let saved = SelectionCapture.snapshotPasteboard(pb)
        #expect(saved.isEmpty)
        // Nothing to put back, so nothing is cleared either.
        SelectionCapture.restorePasteboard(pb, from: saved)
        #expect((pb.types ?? []).isEmpty)
    }
}
