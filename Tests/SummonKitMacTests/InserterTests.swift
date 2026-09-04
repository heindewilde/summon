import AppKit
import Foundation
import Testing
@testable import SummonKit
@testable import SummonKitMac

/// Uses a private, named pasteboard so running the suite never touches the real one.
@Suite("Pasteboard")
@MainActor
struct InserterTests {
    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.heindewilde.summon.tests.\(UUID().uuidString)"))
    }

    @Test("A plain snippet arrives as text")
    func plainText() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        Inserter().writeToPasteboard(InsertPayload(plainText: "Payment terms: 30 days."), to: pb)
        #expect(pb.string(forType: .string) == "Payment terms: 30 days.")
    }

    @Test("A rich snippet carries formatting and a plain-text fallback")
    func richTextWithFallback() throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        let attributed = NSAttributedString(
            string: "Kind regards",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        let rtf = try #require(RTF.data(from: attributed))

        Inserter().writeToPasteboard(InsertPayload(plainText: "Kind regards", rtf: rtf), to: pb)

        #expect(pb.data(forType: .rtf) != nil)
        #expect(pb.string(forType: .string) == "Kind regards")
    }

    @Test("Forcing plain text drops the formatting but keeps the words")
    func plainOnlyDropsRTF() throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        let rtf = try #require(RTF.data(from: NSAttributedString(string: "Kind regards")))
        Inserter().writeToPasteboard(InsertPayload(plainText: "Kind regards", rtf: rtf),
                                     plainOnly: true, to: pb)

        #expect(pb.data(forType: .rtf) == nil)
        #expect(pb.string(forType: .string) == "Kind regards")
    }

    @Test("A file item puts a real file URL on the pasteboard")
    func fileURL() throws {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "summon-test-\(UUID().uuidString).txt")
        try Data("contract".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        Inserter().writeToPasteboard(InsertPayload(fileURL: url), to: pb)

        let read = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        #expect(read?.first?.lastPathComponent == url.lastPathComponent)
    }

    @Test("An empty payload writes nothing rather than wiping the clipboard content")
    func emptyPayload() {
        let pb = scratchPasteboard()
        defer { pb.releaseGlobally() }
        Inserter().writeToPasteboard(InsertPayload(), to: pb)
        #expect(pb.string(forType: .string) == nil)
        #expect(InsertPayload().isEmpty)
    }

    @Test("Toast wording describes the right kind of content")
    func payloadDescription() {
        #expect(InsertPayload(plainText: "x").descriptionForToast == "text")
        #expect(InsertPayload(plainText: "x", rtf: Data()).descriptionForToast == "formatted text")
        #expect(InsertPayload(fileURL: URL(fileURLWithPath: "/tmp/a")).descriptionForToast == "file")
    }
}
