import Foundation
import SwiftData

/// The bytes of an item's file.
///
/// These used to live only on disk, under `Blobs/` or `Vault/`, with `SummonItem`
/// holding a filename. That is a fine arrangement for a single Mac and no arrangement
/// at all for sync: `NSPersistentCloudKitContainer` mirrors the store, so every title,
/// tag and folder would reach a phone and not one byte of a single PDF.
///
/// `@Attribute(.externalStorage)` is what makes this work rather than bloat the
/// database — SwiftData keeps the bytes in a sidecar file and CloudKit mirrors them as
/// a `CKAsset`.
///
/// **Its own entity, not a property on `SummonItem`.** `recordUse` bumps `useCount` and
/// `lastUsedAt` on every single paste, so the item record is the most frequently
/// dirtied thing in the library. Hanging a multi-megabyte asset off it would put the
/// heaviest payload on the noisiest record.
///
/// **Addressed by `itemID`, not by a relationship.** Payloads are tiered by size across
/// two stores — a cloud-eligible one and a local-only one for anything too large to
/// sensibly land on a phone — and Core Data does not allow a relationship to cross a
/// store boundary. A plain UUID does, and it means an item can move between tiers
/// without rewriting the item itself.
///
/// Every attribute is defaulted and nothing is unique, which are CloudKit's rules and
/// the ones the rest of the schema has followed since the first commit.
@Model
public final class SummonPayload {
    /// The item these bytes belong to. Not a relationship — see above.
    public var itemID: UUID = UUID()

    /// Ciphertext for a sealed item, plaintext otherwise. The vault seals before this
    /// ever sees the data, so sealed content crosses iCloud as opaque bytes.
    @Attribute(.externalStorage) public var bytes: Data = Data()

    public var originalName: String = ""
    public var fileExtension: String = ""
    public var isSealed: Bool = false
    public var byteSize: Int = 0
    public var contentHash: String = ""
    public var createdAt: Date = Date.distantPast

    public init(itemID: UUID,
                bytes: Data,
                originalName: String = "",
                fileExtension: String = "",
                isSealed: Bool = false,
                contentHash: String = "",
                createdAt: Date = .now) {
        self.itemID = itemID
        self.bytes = bytes
        self.originalName = originalName
        self.fileExtension = fileExtension
        self.isSealed = isSealed
        self.byteSize = bytes.count
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}
