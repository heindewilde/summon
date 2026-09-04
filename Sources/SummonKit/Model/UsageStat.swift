import Foundation
import SwiftData

/// How often an item is reached for, and from where.
///
/// This is what `SearchIndex` ranks on: frecency with a fourteen-day half-life, and a
/// multiplier for items you have used in the app you are currently in.
///
/// **It lives in a local-only store and does not sync.** Two reasons, one practical
/// and one about what the numbers mean.
///
/// Practically, `recordUse` fires on every single paste. With these counters on
/// `SummonItem` — where they used to be — the most frequently written value in the
/// library sat on the largest and most-mirrored record, so the summon moment itself
/// would have produced a CloudKit write every time.
///
/// And a phone is not a small Mac. What you reach for at a desk is not what you reach
/// for on a train, and `AppAffinity` is keyed by macOS bundle identifiers that mean
/// nothing on iOS — a keyboard extension cannot even learn which app is hosting it. A
/// device learning its own habits is the more useful answer as well as the cheaper one.
@Model
public final class UsageStat {
    /// The item these counts belong to. Not a relationship: this record is in a
    /// different store from `SummonItem`, and Core Data will not let a relationship
    /// cross that boundary.
    public var itemID: UUID = UUID()

    public var useCount: Int = 0
    public var lastUsedAt: Date?

    /// Bundle identifier → how many times this item was used while that app was
    /// frontmost. Was its own `AppAffinity` entity with a relationship; a dictionary
    /// says the same thing without a second table or a cascade rule.
    public var affinity: [String: Int] = [:]

    public init(itemID: UUID, useCount: Int = 0, lastUsedAt: Date? = nil,
                affinity: [String: Int] = [:]) {
        self.itemID = itemID
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.affinity = affinity
    }

    /// Records one use, optionally attributed to the app it happened in.
    func record(inApp bundleID: String?) {
        useCount += 1
        lastUsedAt = Date()
        if let bundleID, !bundleID.isEmpty {
            affinity[bundleID, default: 0] += 1
        }
    }
}
