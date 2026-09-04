import CryptoKit
import Foundation
import UniformTypeIdentifiers

public struct StoredBlob: Sendable, Equatable {
    public var filename: String
    public var byteSize: Int
    public var contentHash: String
    public var isSealed: Bool
    /// The original file extension, kept so sealed blobs can be materialised correctly.
    public var fileExtension: String
    public var originalName: String
}

public enum FileStoreError: Error, LocalizedError {
    case unreadable(URL)
    case missingBlob(String)
    case needsUnlock
    case tooLarge(URL, Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): return "Could not read \(url.lastPathComponent)."
        case .missingBlob(let name): return "The stored file \(name) is missing."
        case .needsUnlock: return "Unlock Summon to open this item."
        case .tooLarge(let url, let size):
            let limit = ByteCountFormatter.string(fromByteCount: Int64(FileStore.maximumImportBytes),
                                                  countStyle: .file)
            let actual = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return "\(url.lastPathComponent) is \(actual). Summon holds files up to \(limit)."
        }
    }
}

/// Copies imported content into the managed library so items are self-contained,
/// survive the original being moved or deleted, and can be genuinely encrypted.
///
/// Stateless and thread-safe: it is pure file I/O over the paths it is given.
public struct FileStore: Sendable {
    public let paths: LibraryPaths

    public init(paths: LibraryPaths) { self.paths = paths }

    // MARK: - Locations

    public func location(of blob: StoredBlob) -> URL {
        (blob.isSealed ? paths.vault : paths.blobs).appending(path: blob.filename)
    }

    public func location(filename: String, sealed: Bool) -> URL {
        (sealed ? paths.vault : paths.blobs).appending(path: filename)
    }

    // MARK: - Import

    /// The largest single file Summon will take in.
    ///
    /// Import reads the whole file into memory to hash it, and sealing it makes a
    /// second copy of the same size, so a dropped disk image was two copies of a disk
    /// image in RAM. This is a library of things you reuse — the canned reply, the
    /// portfolio PDF — and 256 MB is far above anything that fits that description.
    public static let maximumImportBytes = 256 * 1024 * 1024

    public func importFile(at url: URL, itemID: UUID, key: VaultKey?) throws -> StoredBlob {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= FileStore.maximumImportBytes else {
            throw FileStoreError.tooLarge(url, size)
        }
        guard let data = try? Data(contentsOf: url) else { throw FileStoreError.unreadable(url) }
        return try store(data, itemID: itemID, fileExtension: url.pathExtension,
                         originalName: url.lastPathComponent, key: key)
    }

    public func importData(
        _ data: Data,
        itemID: UUID,
        fileExtension: String,
        originalName: String? = nil,
        key: VaultKey?
    ) throws -> StoredBlob {
        try store(data, itemID: itemID, fileExtension: fileExtension,
                  originalName: originalName ?? "Untitled.\(fileExtension)", key: key)
    }

    private func store(
        _ data: Data,
        itemID: UUID,
        fileExtension: String,
        originalName: String,
        key: VaultKey?
    ) throws -> StoredBlob {
        paths.createDirectories()
        let hash = FileStore.hash(data)
        let sealed = key != nil

        let payload: Data
        let filename: String
        if let key {
            payload = try key.seal(data, itemID: itemID)
            filename = "\(itemID.uuidString).enc"
        } else {
            payload = data
            let ext = fileExtension.isEmpty ? "bin" : fileExtension
            filename = "\(itemID.uuidString).\(ext)"
        }

        let destination = location(filename: filename, sealed: sealed)
        try payload.write(to: destination, options: .atomic)

        return StoredBlob(filename: filename, byteSize: data.count, contentHash: hash,
                          isSealed: sealed, fileExtension: fileExtension,
                          originalName: originalName)
    }

    // MARK: - Read

    /// The bytes as they sit on disk, without decrypting.
    ///
    /// The fallback path now that `LibraryStore` reads payloads from the store first.
    public func read(rawOnly blob: StoredBlob) throws -> Data {
        guard let raw = try? Data(contentsOf: location(of: blob)) else {
            throw FileStoreError.missingBlob(blob.filename)
        }
        return raw
    }

    public func read(_ blob: StoredBlob, itemID: UUID, key: VaultKey?) throws -> Data {
        let raw = try read(rawOnly: blob)
        guard blob.isSealed else { return raw }
        guard let key else { throw FileStoreError.needsUnlock }
        return try key.open(raw, itemID: itemID)
    }

    /// Produces a real file on disk that another app can open. For sealed content
    /// this is a decrypted copy in a temporary directory that is wiped on quit.
    public func materialize(_ blob: StoredBlob, itemID: UUID, key: VaultKey?) throws -> URL {
        guard blob.isSealed else { return location(of: blob) }
        return try scratch(try read(blob, itemID: itemID, key: key), for: blob, itemID: itemID)
    }

    /// A decrypted copy in the temporary directory that is wiped on lock and on quit.
    public func scratch(_ data: Data, for blob: StoredBlob, itemID: UUID) throws -> URL {
        let dir = FileStore.scratchDirectory()
        let url = dir.appending(path: FileStore.scratchName(for: blob, itemID: itemID))

        // Created with its permissions rather than chmod'd afterwards. Writing first
        // and tightening second left a decrypted copy of sealed content at the process
        // umask — normally 0644 — for the moment in between.
        let manager = FileManager.default
        try? manager.removeItem(at: url)
        guard manager.createFile(atPath: url.path, contents: data,
                                 attributes: [.posixPermissions: 0o600])
        else { throw FileStoreError.unreadable(url) }
        return url
    }

    /// A durable copy of unsealed bytes, for opening and revealing.
    ///
    /// Named by content hash, so a rewritten item gets a new file rather than a stale
    /// one, and two items with identical bytes share. Ordinary permissions: this is
    /// plaintext that was never secret, and it is the file another app will open.
    public func cached(_ data: Data, for blob: StoredBlob, itemID: UUID) throws -> URL {
        try? FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        // Named by item first and content second: the hash alone would be
        // unrevokable, and marking an item sensitive has to be able to destroy every
        // plaintext copy of it. The hash still means a rewritten item gets a new file
        // rather than a stale one.
        let ext = blob.fileExtension.isEmpty ? "bin" : blob.fileExtension
        let stem = "\(itemID.uuidString)-\(blob.contentHash.prefix(16))"
        let url = paths.cache.appending(path: "\(stem).\(ext)")

        if let existing = try? Data(contentsOf: url), existing == data { return url }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Destroys every cached copy of one item.
    ///
    /// Called when an item becomes sensitive. The cache holds plaintext that was never
    /// secret until the moment someone decides it is, and leaving a readable copy
    /// behind is exactly the leak `scrubSensitiveContent` and the VACUUM exist to
    /// prevent one layer down.
    public func removeCached(itemID: UUID) {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(at: paths.cache,
                                                        includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.lastPathComponent.hasPrefix(itemID.uuidString) {
            try? manager.removeItem(at: url)
        }
    }

    /// A filename that cannot escape the scratch directory.
    ///
    /// `originalName` is stored metadata, and every current writer of it is either a
    /// `lastPathComponent` — which cannot contain a separator — or a generated string.
    /// But it is appended straight onto a path, and `importData(originalName:)` is
    /// public, so this is one careless caller away from writing outside the directory.
    static func scratchName(for blob: StoredBlob, itemID: UUID) -> String {
        let fallback = "\(itemID.uuidString).\(blob.fileExtension.isEmpty ? "bin" : blob.fileExtension)"
        // `lastPathComponent` strips any directory part; the rest rules out the names
        // that traverse without one.
        let candidate = (blob.originalName as NSString).lastPathComponent
        guard !candidate.isEmpty, candidate != ".", candidate != ".." else { return fallback }
        return candidate
    }

    // MARK: - Sensitivity transitions

    /// Encrypts an existing plaintext blob in place.
    public func seal(_ blob: StoredBlob, itemID: UUID, key: VaultKey) throws -> StoredBlob {
        guard !blob.isSealed else { return blob }
        let data = try read(blob, itemID: itemID, key: nil)
        let old = location(of: blob)
        var updated = blob
        updated.filename = "\(itemID.uuidString).enc"
        updated.isSealed = true
        try key.seal(data, itemID: itemID).write(to: location(of: updated), options: .atomic)
        try? FileManager.default.removeItem(at: old)
        return updated
    }

    /// Decrypts a sealed blob back to plaintext storage.
    public func unseal(_ blob: StoredBlob, itemID: UUID, key: VaultKey) throws -> StoredBlob {
        guard blob.isSealed else { return blob }
        let data = try read(blob, itemID: itemID, key: key)
        let old = location(of: blob)
        var updated = blob
        let ext = blob.fileExtension.isEmpty ? "bin" : blob.fileExtension
        updated.filename = "\(itemID.uuidString).\(ext)"
        updated.isSealed = false
        try data.write(to: location(of: updated), options: .atomic)
        try? FileManager.default.removeItem(at: old)
        return updated
    }

    // MARK: - Delete

    public func delete(_ blob: StoredBlob) {
        try? FileManager.default.removeItem(at: location(of: blob))
    }

    public func deleteThumbnail(itemID: UUID) {
        try? FileManager.default.removeItem(at: thumbnailURL(itemID: itemID))
    }

    public func thumbnailURL(itemID: UUID) -> URL {
        paths.thumbnails.appending(path: "\(itemID.uuidString).png")
    }

    // MARK: - Helpers

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Total bytes held by the library, for the storage readout in Settings.
    public func totalBytes() -> Int {
        var total = 0
        for dir in [paths.blobs, paths.vault, paths.thumbnails] {
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let url as URL in e {
                total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        total += (try? paths.storeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return total
    }

    private static let scratchDirectoryName = "Summon-Scratch"

    public static func scratchDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: scratchDirectoryName)
        let manager = FileManager.default
        try? manager.createDirectory(at: dir, withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: 0o700])
        // Re-asserted: the attribute above only applies when this call is the one that
        // creates the directory, and a directory left over from an earlier run — or
        // created by something else — would keep whatever mode it already had.
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Wipes decrypted temporary copies.
    ///
    /// Called at launch as well as at quit, on lock, and when the panel closes. The
    /// exit paths cannot cover a crash or a force-quit, which would otherwise leave
    /// plaintext copies of sealed files in the temporary directory indefinitely —
    /// clearing on the way in is what puts a bound on that.
    public static func clearScratch() {
        try? FileManager.default.removeItem(at: scratchDirectory())
    }
}
