import Foundation

/// Where Summon keeps everything. All on-device, under Application Support.
///
/// `SUMMON_DEMO=1` redirects the whole library into a throwaway container so the
/// app can be exercised and screenshotted without touching a real library.
public struct LibraryPaths: Sendable {
    /// The library itself. In a shipping build this is inside the App Group container,
    /// so the share and action extensions can reach the same store the app does.
    public let root: URL

    /// The part that belongs to *this device* rather than to the library: the wrapped
    /// vault key and the record of wrong guesses. Deliberately outside the group
    /// container — nothing here may ever travel, and an extension has no business
    /// reading it. Equal to `root` for tests and for a library built by hand.
    public let deviceRoot: URL

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
    public var vaultKeyFile: URL { deviceRoot.appending(path: "vault.wrap") }

    /// Wrong guesses and when the last one happened. **Never syncs.**
    ///
    /// Kept apart from `vault.wrap` because the two are different kinds of thing. The
    /// wrapper is the vault; the throttle is a property of *the device being attacked*.
    /// Syncing it down would be a bypass — a stale, lower count clears a cooldown
    /// someone else is serving — and syncing it up would be a denial of service, since
    /// anyone able to guess wrongly on one device could lock you out of another.
    ///
    /// Two devices therefore means two independent attempt budgets. That is inherent to
    /// unlocking on more than one machine, the per-device cooldown still holds, and it
    /// belongs in Known Limits rather than in a comment.
    public var vaultThrottleFile: URL { deviceRoot.appending(path: "vault.throttle.json") }

    /// Which one-off repairs this library has already had. Per-library rather than
    /// per-user: the demo library and a real one are at different versions, and a
    /// preference shared between them would claim work on one had been done on both.
    public var migrationsFile: URL { root.appending(path: "migrations.json") }

    public init(root: URL, deviceRoot: URL? = nil) {
        self.root = root
        self.deviceRoot = deviceRoot ?? root
    }

    public static var isDemoMode: Bool {
        ProcessInfo.processInfo.environment["SUMMON_DEMO"] == "1"
    }

    /// The App Group the app and its extensions share.
    ///
    /// macOS requires the Team ID prefix; iOS requires its absence. The two therefore
    /// name different containers, which costs nothing: a group container is shared
    /// between processes on one device, never between devices.
    public static let appGroupID: String = {
        #if os(macOS)
        "JV4MVRB77Q.group.com.heindewilde.summon"
        #else
        "group.com.heindewilde.summon"
        #endif
    }()

    private static var folderName: String { isDemoMode ? "Summon-Demo" : "Summon" }

    /// Where the library lives for a normal launch.
    ///
    /// The group container when the entitlement grants one, which is every signed
    /// build. A plain `swift build` has no entitlements, so it falls back to
    /// Application Support and behaves as the app always did.
    public static func standard() -> LibraryPaths {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        let paths = LibraryPaths(
            root: (group ?? applicationSupport).appending(path: folderName),
            deviceRoot: applicationSupport.appending(path: folderName))
        paths.createDirectories()
        return paths
    }

    /// True when the library is in the App Group container rather than the fallback.
    /// The self-test asserts this of a signed build, because a silent fallback would
    /// mean the extensions were writing somewhere the app never reads.
    public var isInAppGroupContainer: Bool {
        guard let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else { return false }
        return root.path().hasPrefix(group.path())
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
        for dir in [root, deviceRoot, blobs, vault, thumbnails, cache] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func destroy() {
        try? FileManager.default.removeItem(at: root)
    }
}
