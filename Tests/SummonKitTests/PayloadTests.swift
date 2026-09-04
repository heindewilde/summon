import Foundation
import SwiftData
import Testing
@testable import SummonKit

/// The entity that will hold every byte in the library once the migration lands.
///
/// Its shape is asserted here rather than trusted, because CloudKit freezes a schema
/// at Production promotion: fields can be added afterwards, never removed or renamed.
@Suite("Payload storage")
@MainActor
struct PayloadTests {

    private func store() throws -> (LibraryStore, LibraryPaths) {
        let paths = LibraryPaths.temporary()
        return (try LibraryStore(paths: paths, vault: Vault(paths: paths)), paths)
    }

    @Test("Bytes round-trip through the store")
    func roundTrip() throws {
        let (store, paths) = try store()
        defer { paths.destroy() }

        let id = UUID()
        let data = Data("quarterly figures".utf8)
        store.context.insert(SummonPayload(itemID: id, bytes: data,
                                           originalName: "Report.pdf",
                                           fileExtension: "pdf",
                                           contentHash: FileStore.hash(data)))
        try store.context.save()

        let found = try store.context.fetch(FetchDescriptor<SummonPayload>())
        #expect(found.count == 1)
        #expect(found.first?.bytes == data)
        #expect(found.first?.byteSize == data.count)
        #expect(found.first?.contentHash == FileStore.hash(data))
    }

    /// Large enough to exercise `.externalStorage`, which is the whole reason this
    /// entity can carry a PDF without turning the database into one.
    @Test("A payload larger than the inline threshold survives intact")
    func externalStorage() throws {
        let (store, paths) = try store()
        defer { paths.destroy() }

        let data = Data((0..<(512 * 1024)).map { UInt8($0 % 251) })
        let id = UUID()
        store.context.insert(SummonPayload(itemID: id, bytes: data, contentHash: FileStore.hash(data)))
        try store.context.save()

        let found = try #require(try store.context.fetch(FetchDescriptor<SummonPayload>()).first)
        #expect(found.bytes == data, "external storage must not alter the bytes")
        #expect(found.byteSize == data.count)
    }

    /// Sealed content reaches this entity already encrypted, and must stay that way —
    /// this is what lets a locked item cross iCloud as bytes Apple cannot read.
    @Test("A sealed payload holds ciphertext and no plaintext")
    func sealedStaysSealed() throws {
        let (store, paths) = try store()
        defer { paths.destroy() }

        let key = VaultKey.generate()
        let id = UUID()
        let plaintext = Data("NL91 ABNA 0417 1643 00".utf8)
        let sealed = try key.seal(plaintext, itemID: id)

        store.context.insert(SummonPayload(itemID: id, bytes: sealed, isSealed: true))
        try store.context.save()

        let found = try #require(try store.context.fetch(FetchDescriptor<SummonPayload>()).first)
        #expect(found.isSealed)
        #expect(found.bytes != plaintext)
        #expect(found.bytes.range(of: plaintext) == nil, "plaintext must not survive in the record")
        #expect(try key.open(found.bytes, itemID: id) == plaintext)
    }

    /// CloudKit refuses a schema with a unique constraint, and every attribute must
    /// have a default. Two items can legitimately share a hash, and a payload can
    /// legitimately arrive before the item it belongs to.
    @Test("Two payloads may share an item id and a hash")
    func noUniqueConstraints() throws {
        let (store, paths) = try store()
        defer { paths.destroy() }

        let id = UUID()
        let data = Data("same".utf8)
        store.context.insert(SummonPayload(itemID: id, bytes: data, contentHash: FileStore.hash(data)))
        store.context.insert(SummonPayload(itemID: id, bytes: data, contentHash: FileStore.hash(data)))
        try store.context.save()

        #expect(try store.context.fetch(FetchDescriptor<SummonPayload>()).count == 2)
    }
}
