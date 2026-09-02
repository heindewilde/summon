import Foundation

/// Where Summon keeps everything. All on-device, under Application Support.
///
/// `SUMMON_DEMO=1` redirects the whole library into a throwaway container so the
/// app can be exercised and screenshotted without touching a real library.
public struct LibraryPaths: Sendable {
    public let root: URL

    public var storeURL: URL { root.appending(path: "Library.store") }
    public var blobs: URL { root.appending(path: "Blobs") }
    public var vault: URL { root.appending(path: "Vault") }
    public var thumbnails: URL { root.appending(path: "Thumbnails") }
    public var vaultKeyFile: URL { root.appending(path: "vault.wrap") }

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
        for dir in [root, blobs, vault, thumbnails] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func destroy() {
        try? FileManager.default.removeItem(at: root)
    }
}
