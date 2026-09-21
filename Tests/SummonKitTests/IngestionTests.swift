import Foundation
import Testing
@testable import SummonKit

/// The share extension's half of the app, which runs where nobody can watch it: a
/// process with seconds to live, no window, and no way to report a problem except by
/// refusing. These are the two things it must get right.
@Suite("Ingestion")
@MainActor
struct IngestionTests {
    @Test("Text saved by an extension lands in the library")
    func savesText() async throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let ingestion = try Ingestion(paths: paths)

        let title = try await ingestion.save(.text("Payment terms are 30 days.", rtf: nil))
        #expect(!title.isEmpty)

        // Reopened from disk, because the point is that another process can see it.
        let store = try LibraryStore(paths: paths, vault: Vault(paths: paths, syncsMasterKey: false),
                                     syncs: false)
        #expect(store.snapshots.count == 1)
        #expect(store.snapshots.first?.searchableText.contains("30 days") == true)
    }

    @Test("Empty text is refused rather than saved as a blank")
    func refusesEmptyText() async throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let ingestion = try Ingestion(paths: paths)

        await #expect(throws: Ingestion.Failure.nothingUsable) {
            try await ingestion.save(.text("   \n  ", rtf: nil))
        }
    }

    @Test("A library still holding blobs outside the store is left to the app")
    func refusesUnmigratedLibrary() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }

        // A library as it was before payloads moved into the store: an item pointing at
        // a file, and no payload row for it.
        let store = try LibraryStore(paths: paths, vault: Vault(paths: paths, syncsMasterKey: false),
                                     syncs: false)
        let file = paths.blobs.appending(path: "legacy.txt")
        try "older than this build".write(to: file, atomically: true, encoding: .utf8)
        let item = store.createSnippet(title: "Legacy", body: "")
        item.blobFilename = "legacy.txt"
        item.blobExtension = "txt"
        item.blobOriginalName = "legacy.txt"
        store.save()

        // Migrating rewrites every payload in the library. An extension that started
        // that and was killed halfway would leave the mess for the app to find, so it
        // declines instead — and says which door to use.
        #expect(store.hasUnmigratedPayloads())
        #expect(throws: Ingestion.Failure.needsTheApp) { try Ingestion(paths: paths) }
    }
}
