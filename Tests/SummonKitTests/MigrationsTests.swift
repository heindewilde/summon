import Foundation
import Testing
@testable import SummonKit

/// The migration bookkeeping, which had a way of quietly undoing itself.
@Suite("Migration bookkeeping")
struct MigrationsTests {

    /// The regression this exists for.
    ///
    /// Swift's synthesised `Decodable` emits `try container.decode` for a non-optional
    /// stored property and does not fall back to its declared default when the key is
    /// missing. `loadMigrations` swallows a decode failure and returns a fresh
    /// `Migrations()`, so adding any second field would have silently reset every
    /// existing library to version 0 and re-run the whole scrub — a full re-seal pass
    /// and a VACUUM — with nothing to explain it.
    @Test("A record written by an older version still decodes")
    func olderRecordDecodes() throws {
        // Exactly what today's encoder writes.
        let v1 = Data(#"{"scrubVersion":1}"#.utf8)
        let decoded = try JSONDecoder().decode(LibraryStore.Migrations.self, from: v1)
        #expect(decoded.scrubVersion == 1)
    }

    /// And the shape the *next* version will read: a file written before a field
    /// existed must not look like a library that was never migrated.
    @Test("A record missing a newer field keeps the version it had")
    func missingFieldKeepsVersion() throws {
        let withExtra = Data(#"{"scrubVersion":1,"payloadVersion":2}"#.utf8)
        let decoded = try JSONDecoder().decode(LibraryStore.Migrations.self, from: withExtra)
        #expect(decoded.scrubVersion == 1, "an unknown key must be ignored, not fatal")

        let empty = Data("{}".utf8)
        #expect(try JSONDecoder().decode(LibraryStore.Migrations.self, from: empty).scrubVersion == 0)
    }

    @Test("A round trip through the store's own load and save preserves the version")
    @MainActor func roundTrip() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let store = try LibraryStore(paths: paths, vault: Vault(paths: paths))

        #expect(store.loadMigrations().scrubVersion == 0, "a fresh library has run nothing")

        var record = store.loadMigrations()
        record.scrubVersion = LibraryStore.currentScrubVersion
        store.save(record)

        #expect(store.loadMigrations().scrubVersion == LibraryStore.currentScrubVersion)
    }
}
