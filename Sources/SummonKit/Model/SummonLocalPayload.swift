import Foundation
import SwiftData

/// A payload too large to sensibly send to a phone.
///
/// `NSPersistentCloudKitContainer` mirrors eagerly and totally: there is no lazy asset
/// fetch, no per-record policy and no cellular gate, so every device that joins the
/// zone downloads every asset. Without a ceiling, a scanned book or a screen recording
/// would try to land on an iPhone in full, over whatever connection it happened to
/// have. That is the failure most likely to make a companion unusable, and it is
/// invisible until the first sync.
///
/// So anything over `LibraryStore.cloudPayloadLimit` goes here instead, in the same
/// local-only store as `UsageStat`. The item still syncs — its title, tags, folder and
/// notes are all findable on the phone — and the file itself stays where it is, shown
/// as living on the Mac.
///
/// Identical in shape to `SummonPayload` rather than sharing a type with a flag,
/// because which store a record lives in is decided by its type. Both are addressed by
/// `itemID`, which is what lets an item change tier without being rewritten.
@Model
public final class SummonLocalPayload {
    public var itemID: UUID = UUID()

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
