import Foundation

/// Where Summon keeps everything. All on-device, under Application Support.
///
/// `SUMMON_DEMO=1` redirects the whole library into a throwaway container so the
/// app can be exercised and screenshotted without touching a real library.
public struct LibraryPaths: Sendable {
    public let root: URL

    public var storeURL: URL { root.appending(path: "Library.store") }

    /// The half of the library that stays on this device.
    ///
    /// A second store rather than a flag on a row, because "does not sync" is a
    /// property of the store in Core Data, not of a record. It holds usage counts and
    /// any payload too large to sensibly land on a phone.
    public var localStoreURL: URL { root.appending(path: "Library-Local.store") }
    public var blobs: URL { root.appending(path: "Blobs") }
    public var vault: URL { root.appending(path: "Vault") }
    public var thumbnails: URL { root.appending(path: "Thumbnails") }

    /// Decrypted-nothing, throw-away copies of unsealed payloads.
    ///
    /// Once the bytes live in the store there is no managed file to hand another app,
    /// and `materialize` would otherwise have to write a temporary copy every time —
    /// which also means "Reveal in Finder" would point at a file in /tmp. This is a
    /// cache, not storage: the store is the source of truth and anything here can be
    /// deleted and rebuilt. Sealed content never lands here; it goes to the scratch
    /// directory that is wiped on lock and on quit.
    public var cache: URL { root.appending(path: "Cache") }
    public var vaultKeyFile: URL { root.appending(path: "vault.wrap") }

    /// Which one-off repairs this library has already had. Per-library rather than
    /// per-user: the demo library and a real one are at different versions, and a
    /// preference shared between them would claim work on one had been done on both.
    public var migrationsFile: URL { root.appending(path: "migrations.json") }

    public init(root: URL) { self.root = root }

    public static var isDemoMode: Bool {
        ProcessInfo.processInfo.environment["SUMMON_DEMO"] == "1"
    }

    public static func standard() -> LibraryPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = isDemoMode
            ? base.appending(path: "Summon-Demo")
            : base.appending(path: "Summon")
        let paths = LibraryPaths(root: root)
        paths.createDirectories()
        return paths
    }

    /// An isolated library, used by tests.
    public static func temporary() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "SummonTests-\(UUID().uuidString)")
        let paths = LibraryPaths(root: root)
        paths.createDirectories()
        return paths
    }

    public func createDirectories() {
        for dir in [root, blobs, vault, thumbnails, cache] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func destroy() {
        try? FileManager.default.removeItem(at: root)
    }
}
