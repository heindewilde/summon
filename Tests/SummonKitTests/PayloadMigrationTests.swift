import Foundation
import SwiftData
import Testing
@testable import SummonKit

/// Moving every byte in a real library is the single most destructive thing in this
/// project, so the fixtures come first and the properties are the ones that matter
/// when it goes wrong halfway: it must converge, it must be safe to run twice, it
/// must resume, and ciphertext must come back bit for bit.
@Suite("Payload migration")
@MainActor
struct PayloadMigrationTests {

    private func library() throws -> (LibraryStore, LibraryPaths) {
        let paths = LibraryPaths.temporary()
        return (try LibraryStore(paths: paths, vault: Vault(paths: paths)), paths)
    }

    /// A file on disk with an item pointing at it — the shape every existing library
    /// is in today.
    @discardableResult
    private func legacyItem(_ store: LibraryStore, name: String, body: String,
                            sealed: Bool = false) throws -> UUID {
        let data = Data(body.utf8)
        let item = try #require(store.importData(data, title: name, kind: .document,
                                                 fileExtension: "pdf", originalName: name))
        if sealed { try store.setSensitive(item, true) }
        return item.id
    }

    @Test("Every blob on disk arrives in the store")
    func converges() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let a = try legacyItem(store, name: "Report.pdf", body: "quarterly figures")
        let b = try legacyItem(store, name: "Terms.pdf", body: "terms and conditions")

        let moved = store.migratePayloads()
        #expect(moved == 2)

        let payloads = try store.context.fetch(FetchDescriptor<SummonPayload>())
        #expect(Set(payloads.map(\.itemID)) == Set([a, b]))
        #expect(payloads.first { $0.itemID == a }?.bytes == Data("quarterly figures".utf8))
    }

    @Test("Running it again moves nothing and duplicates nothing")
    func idempotent() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        try legacyItem(store, name: "Report.pdf", body: "quarterly figures")
        #expect(store.migratePayloads() == 1)
        #expect(store.migratePayloads() == 0, "a second pass has nothing left to do")
        #expect(try store.context.fetch(FetchDescriptor<SummonPayload>()).count == 1)
    }

    /// The interrupted case. A crash halfway leaves some items migrated and some not,
    /// and the next launch has to pick up exactly where it stopped — which is why the
    /// marker is "a payload exists for this item" rather than a counter somewhere.
    @Test("An interrupted run resumes where it stopped")
    func resumes() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let ids = try (0..<5).map { try legacyItem(store, name: "F\($0).pdf", body: "body \($0)") }

        // Simulate having got through the first two before dying.
        for id in ids.prefix(2) {
            let blob = try #require(store.item(id: id)?.storedBlob)
            let bytes = try store.files.read(blob, itemID: id, key: nil)
            store.context.insert(SummonPayload(itemID: id, bytes: bytes))
        }
        try store.context.save()

        #expect(store.migratePayloads() == 3, "only the unmigrated three")
        let payloads = try store.context.fetch(FetchDescriptor<SummonPayload>())
        #expect(payloads.count == 5)
        #expect(Set(payloads.map(\.itemID)) == Set(ids))
    }

    /// Sealed content must cross without being opened. The migration has no key and
    /// must never need one — it moves ciphertext, byte for byte, and the same key
    /// still opens it afterwards.
    @Test("Sealed bytes migrate without a key and still open with the old one")
    func sealedSurvives() async throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        try await store.vault.setUpSecret("1234", kind: .pin)
        let key = try #require(store.vault.currentKey)
        let id = try legacyItem(store, name: "Passport.pdf", body: "passport scan", sealed: true)

        let blob = try #require(store.item(id: id)?.storedBlob)
        #expect(blob.isSealed)
        let onDisk = try Data(contentsOf: store.files.location(of: blob))

        store.vault.lock()
        #expect(store.migratePayloads() == 1, "a locked vault must not stop the migration")

        let payload = try #require(try store.context.fetch(FetchDescriptor<SummonPayload>()).first)
        #expect(payload.isSealed)
        #expect(payload.bytes == onDisk, "ciphertext must be byte-identical")
        #expect(try key.open(payload.bytes, itemID: id) == Data("passport scan".utf8))
    }

    /// The source files stay put in this release. They are the orphan detector and the
    /// way back if anything about the new path proves wrong.
    @Test("The original files are left alone")
    func leavesSourcesInPlace() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let id = try legacyItem(store, name: "Report.pdf", body: "quarterly figures")
        let blob = try #require(store.item(id: id)?.storedBlob)

        _ = store.migratePayloads()

        #expect(FileManager.default.fileExists(atPath: store.files.location(of: blob).path))
        #expect(store.item(id: id)?.blobFilename == blob.filename)
    }

    /// The point of the whole exercise: once migrated, the store answers, and the
    /// files under Blobs/ and Vault/ are a fallback rather than the source of truth.
    @Test("Reading survives the source file being deleted")
    func storeIsAuthoritative() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let id = try legacyItem(store, name: "Report.pdf", body: "quarterly figures")
        _ = store.migratePayloads()

        let blob = try #require(store.item(id: id)?.storedBlob)
        try FileManager.default.removeItem(at: store.files.location(of: blob))

        #expect(try store.read(blob, itemID: id, key: nil) == Data("quarterly figures".utf8))

        let url = try store.materialize(blob, itemID: id, key: nil)
        #expect(try Data(contentsOf: url) == Data("quarterly figures".utf8))
        #expect(url.path.hasPrefix(paths.cache.path), "unsealed content is cached, not scratched")
    }

    /// And the other direction, which is what the fallback is for: a library that has
    /// not been migrated yet still resolves off disk.
    @Test("An unmigrated item still reads from disk")
    func fallbackStillWorks() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let id = try legacyItem(store, name: "Report.pdf", body: "quarterly figures")
        #expect(store.storedBytes(for: id) == nil, "not migrated yet")

        let blob = try #require(store.item(id: id)?.storedBlob)
        #expect(try store.read(blob, itemID: id, key: nil) == Data("quarterly figures".utf8))
    }

    /// Marking an item sensitive has to seal the bytes that will sync, not just the
    /// ones on disk — and destroy any readable copy it already handed out.
    @Test("Sealing an item seals its payload and revokes the cached copy")
    func sealingRevokesPlaintext() async throws {
        let (store, paths) = try library()
        defer { paths.destroy() }
        try await store.vault.setUpSecret("1234", kind: .pin)

        let id = try legacyItem(store, name: "Passport.pdf", body: "passport scan")
        _ = store.migratePayloads()

        let blob = try #require(store.item(id: id)?.storedBlob)
        let cached = try store.materialize(blob, itemID: id, key: nil)
        #expect(FileManager.default.fileExists(atPath: cached.path))

        try store.setSensitive(try #require(store.item(id: id)), true)

        let payload = try #require(try store.context.fetch(FetchDescriptor<SummonPayload>()).first)
        #expect(payload.isSealed, "the stored bytes must be sealed, not only the file")
        #expect(payload.bytes.range(of: Data("passport scan".utf8)) == nil,
                "no plaintext may survive in the record that syncs")
        #expect(!FileManager.default.fileExists(atPath: cached.path),
                "the plaintext copy handed out earlier must be destroyed")

        let key = try #require(store.vault.currentKey)
        #expect(try key.open(payload.bytes, itemID: id) == Data("passport scan".utf8))
    }
}
