import Foundation

/// An immutable, `Sendable` projection of a `SummonItem`.
///
/// SwiftData models are main-actor-bound and not `Sendable`, so ranking works on
/// these instead. That also makes the entire search layer testable without a store.
public struct ItemSnapshot: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var kind: ItemKind
    public var tagNames: [String]
    public var folderPath: [String]

    /// The folder the item is filed in directly, if any.
    ///
    /// The path alone could not answer "is this item *in* this folder", which is what
    /// the sidebar needs now that selecting a parent no longer sweeps up its subtree.
    public var folderID: UUID?

    /// Position within that folder's hand-chosen order.
    public var sortIndex: Int

    public var summary: String?

    /// Body plus extracted/OCR text. Empty while the item is locked — which is what
    /// stops a locked item being found by searching its contents.
    public var searchableText: String

    /// A short line shown under the title in results.
    public var previewLine: String

    public var isPinned: Bool
    public var isSensitive: Bool
    public var isLocked: Bool
    public var hasPlaceholders: Bool

    public var useCount: Int
    public var lastUsedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var byteSize: Int

    /// bundle identifier → number of times this item was used while that app was frontmost.
    public var affinity: [String: Int]

    public init(
        id: UUID = UUID(),
        title: String,
        kind: ItemKind = .text,
        tagNames: [String] = [],
        folderPath: [String] = [],
        folderID: UUID? = nil,
        sortIndex: Int = 0,
        summary: String? = nil,
        searchableText: String = "",
        previewLine: String = "",
        isPinned: Bool = false,
        isSensitive: Bool = false,
        isLocked: Bool = false,
        hasPlaceholders: Bool = false,
        useCount: Int = 0,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        byteSize: Int = 0,
        affinity: [String: Int] = [:]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.tagNames = tagNames
        self.folderPath = folderPath
        self.folderID = folderID
        self.sortIndex = sortIndex
        self.summary = summary
        self.searchableText = searchableText
        self.previewLine = previewLine
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.isLocked = isLocked
        self.hasPlaceholders = hasPlaceholders
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.byteSize = byteSize
        self.affinity = affinity
    }

    public var folderLabel: String { folderPath.joined(separator: " › ") }
}
