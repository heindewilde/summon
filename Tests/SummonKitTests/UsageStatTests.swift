import Foundation
import SwiftData
import Testing
@testable import SummonKit

/// Usage history, which now lives in a store of its own and stays on the device.
@Suite("Device-local usage")
@MainActor
struct UsageStatTests {

    private func library() throws -> (LibraryStore, LibraryPaths) {
        let paths = LibraryPaths.temporary()
        return (try LibraryStore(paths: paths, vault: Vault(paths: paths)), paths)
    }

    @Test("Using an item counts, and ranking sees it")
    func recordsUse() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let item = try #require(store.createSnippet(title: "IBAN", body: "NL91"))
        store.recordUse(id: item.id, inApp: "com.apple.mail")
        store.recordUse(id: item.id, inApp: "com.apple.mail")

        let snapshot = try #require(store.snapshots.first { $0.id == item.id })
        #expect(snapshot.useCount == 2)
        #expect(snapshot.lastUsedAt != nil)
        #expect(snapshot.affinity["com.apple.mail"] == 2)
    }

    /// The whole point of the move: the record CloudKit would mirror stays untouched
    /// by the most frequent write in the app.
    @Test("Using an item does not write the synced record")
    func leavesTheItemAlone() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let item = try #require(store.createSnippet(title: "IBAN", body: "NL91"))
        let before = item.updatedAt
        store.recordUse(id: item.id, inApp: "com.apple.mail")

        #expect(item.useCount == 0, "the legacy field is no longer written")
        #expect(item.lastUsedAt == nil)
        #expect(item.updatedAt == before, "a paste must not dirty the item")
        #expect((item.affinities ?? []).isEmpty)
    }

    @Test("Summon itself never earns affinity")
    func ignoresOwnBundle() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let item = try #require(store.createSnippet(title: "IBAN", body: "NL91"))
        store.recordUse(id: item.id, inApp: "com.heindewilde.summon")

        let snapshot = try #require(store.snapshots.first { $0.id == item.id })
        #expect(snapshot.useCount == 1)
        #expect(snapshot.affinity.isEmpty)
    }

    /// An existing library's history has to survive the move, or the ranking everyone
    /// relies on resets to nothing.
    @Test("History on the old fields migrates, once")
    func migratesLegacyHistory() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        let item = try #require(store.createSnippet(title: "IBAN", body: "NL91"))
        // The shape an existing library is in.
        item.useCount = 7
        item.lastUsedAt = Date(timeIntervalSince1970: 1_700_000_000)
        store.context.insert(AppAffinity(bundleID: "com.apple.mail", item: item))
        try store.context.save()
        for stat in try store.context.fetch(FetchDescriptor<UsageStat>()) {
            store.context.delete(stat)
        }
        try store.context.save()

        #expect(store.migrateUsage() == 1)
        #expect(store.migrateUsage() == 0, "a second pass has nothing to do")

        store.refresh()
        let snapshot = try #require(store.snapshots.first { $0.id == item.id })
        #expect(snapshot.useCount == 7)
        #expect(snapshot.lastUsedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(snapshot.affinity["com.apple.mail"] == 1)
    }

    @Test("An item with no history gets no record")
    func skipsUntouchedItems() throws {
        let (store, paths) = try library()
        defer { paths.destroy() }

        _ = try #require(store.createSnippet(title: "Unused", body: "nothing"))
        #expect(store.migrateUsage() == 0)
        #expect(try store.context.fetch(FetchDescriptor<UsageStat>()).isEmpty)
    }
}
