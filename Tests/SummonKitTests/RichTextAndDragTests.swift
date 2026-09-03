import AppKit
import Foundation
import Testing
@testable import SummonKit

@MainActor
private func makeStore() throws -> (LibraryStore, Vault, LibraryPaths) {
    let paths = LibraryPaths.temporary()
    let vault = Vault(paths: paths)
    return (try LibraryStore(paths: paths, vault: vault), vault, paths)
}

private func boldText(_ string: String) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
}

private func isBold(_ attributed: NSAttributedString) -> Bool {
    guard attributed.length > 0,
          let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.bold)
}

@Suite("Rich snippets")
@MainActor
struct RichTextTests {

    @Test("A snippet created with RTF is rich and keeps its formatting")
    func createsRich() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let rtf = try #require(RTF.data(from: boldText("Kind regards")))
        let item = store.createSnippet(title: "Sign-off", body: "Kind regards", rtf: rtf)

        #expect(item.kind == .richText)
        #expect(item.bodyRTF != nil)
        let read = try #require(store.resolveAttributed(item, key: nil))
        #expect(read.string == "Kind regards")
        #expect(isBold(read))
    }

    /// The regression this suite exists for: editing a rich snippet used to call an
    /// update that defaulted `rtf` to nil, silently discarding the formatting and
    /// leaving the item claiming to be rich with no RTF behind it.
    @Test("Editing a rich snippet preserves its formatting")
    func editingKeepsFormatting() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let rtf = try #require(RTF.data(from: boldText("Kind regards")))
        let item = store.createSnippet(title: "Sign-off", body: "Kind regards", rtf: rtf)

        store.updateSnippet(item, attributed: boldText("Kind regards, Hein"))

        #expect(item.kind == .richText)
        #expect(item.bodyRTF != nil)
        let read = try #require(store.resolveAttributed(item, key: nil))
        #expect(read.string == "Kind regards, Hein")
        #expect(isBold(read))
    }

    @Test("A rich item is never left claiming formatting it no longer has")
    func noInconsistentState() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let rtf = try #require(RTF.data(from: boldText("Bold")))
        let item = store.createSnippet(title: "S", body: "Bold", rtf: rtf)

        // Deliberately converting to plain must also change the kind.
        store.updateSnippet(item, plain: "Now plain")
        #expect(item.kind == .text)
        #expect(item.bodyRTF == nil)
        #expect(item.bodyText == "Now plain")
    }

    @Test("Formatting survives being encrypted and decrypted")
    func formattingSurvivesSealing() async throws {
        let (store, vault, paths) = try makeStore()
        defer { paths.destroy() }
        try await vault.setUpPIN("4829")

        let rtf = try #require(RTF.data(from: boldText("Account details")))
        let item = store.createSnippet(title: "Bank", body: "Account details", rtf: rtf)

        try store.setSensitive(item, true)
        #expect(item.sealedBody != nil)
        #expect(item.bodyRTF == nil)

        let whileUnlocked = try #require(store.resolveAttributed(item, key: vault.currentKey))
        #expect(isBold(whileUnlocked))

        vault.lock()
        #expect(store.resolveAttributed(item, key: nil) == nil)

        try await vault.unlock(pin: "4829")
        try store.setSensitive(item, false)
        let restored = try #require(store.resolveAttributed(item, key: nil))
        #expect(restored.string == "Account details")
        #expect(isBold(restored))
    }

    @Test("A rich snippet still pastes as text in apps that cannot take RTF")
    func richPayloadCarriesPlainFallback() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let rtf = try #require(RTF.data(from: boldText("Kind regards")))
        let item = store.createSnippet(title: "Sign-off", body: "Kind regards", rtf: rtf)

        let payload = try #require(store.payload(for: item.id))
        #expect(payload.rtf != nil)
        #expect(payload.plainText == "Kind regards")
    }
}

@Suite("Dragging")
struct DragProviderTests {

    @Test("A document drags as a real file, not as its title")
    func fileDragsAsFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "summon-drag-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4 fake".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = try #require(DragProvider.make(for: InsertPayload(fileURL: url),
                                                      title: "Studio One Pager"))
        #expect(!provider.registeredTypeIdentifiers.isEmpty)
        #expect(provider.suggestedName == url.lastPathComponent)
        // The old behaviour vended only the title string; a file drag must not.
        #expect(provider.registeredTypeIdentifiers.contains { $0.contains("pdf") || $0.contains("data") })
    }

    @Test("A snippet drags its text")
    func snippetDragsText() throws {
        let provider = try #require(DragProvider.make(
            for: InsertPayload(plainText: "Payment terms: 30 days."), title: "Terms"))
        #expect(provider.registeredTypeIdentifiers.contains { $0.contains("plain-text") || $0.contains("text") })
        #expect(provider.suggestedName == "Terms")
    }

    @Test("A rich snippet drags formatting alongside plain text")
    func richSnippetDragsBoth() throws {
        let rtf = try #require(RTF.data(from: boldText("Kind regards")))
        let provider = try #require(DragProvider.make(
            for: InsertPayload(plainText: "Kind regards", rtf: rtf), title: "Sign-off"))
        let types = provider.registeredTypeIdentifiers
        #expect(types.contains { $0.contains("rtf") })
        #expect(types.contains { $0.contains("text") })
    }

    @Test("Nothing to drag yields no provider rather than an empty one")
    func emptyPayloadNoProvider() {
        #expect(DragProvider.make(for: InsertPayload(), title: "Untitled") == nil)
    }

    @Test("A missing file falls through instead of vending a broken promise")
    func missingFile() {
        let missing = URL(fileURLWithPath: "/tmp/summon-does-not-exist-\(UUID().uuidString).pdf")
        #expect(DragProvider.make(for: InsertPayload(fileURL: missing), title: "Gone") == nil)
    }
}
