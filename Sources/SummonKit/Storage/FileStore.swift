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

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Could not read \(url.lastPathComponent)."
        case .missingBlob(let name): "The stored file \(name) is missing."
        case .needsUnlock: "Unlock Summon to open this item."
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

    public func importFile(at url: URL, itemID: UUID, key: VaultKey?) throws -> StoredBlob {
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

    public func read(_ blob: StoredBlob, itemID: UUID, key: VaultKey?) throws -> Data {
        let url = location(of: blob)
        guard let raw = try? Data(contentsOf: url) else { throw FileStoreError.missingBlob(blob.filename) }
        guard blob.isSealed else { return raw }
        guard let key else { throw FileStoreError.needsUnlock }
        return try key.open(raw, itemID: itemID)
    }

    /// Produces a real file on disk that another app can open. For sealed content
    /// this is a decrypted copy in a temporary directory that is wiped on quit.
    public func materialize(_ blob: StoredBlob, itemID: UUID, key: VaultKey?) throws -> URL {
        guard blob.isSealed else { return location(of: blob) }
        let data = try read(blob, itemID: itemID, key: key)
        let dir = FileStore.scratchDirectory()
        let name = blob.originalName.isEmpty ? "\(itemID.uuidString).\(blob.fileExtension)" : blob.originalName
        let url = dir.appending(path: name)
        try data.write(to: url, options: .atomic)
        // Readable only by this user; removed wholesale at quit.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
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

    private static let scratchName = "Summon-Scratch"

    public static func scratchDirectory() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: scratchName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }

    /// Wipes decrypted temporary copies. Called at quit and whenever the vault locks.
    public static func clearScratch() {
        try? FileManager.default.removeItem(at: scratchDirectory())
    }
}
