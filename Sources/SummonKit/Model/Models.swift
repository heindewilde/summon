import Foundation
import SwiftData

// The schema follows CloudKit's rules from day one — no unique constraints, every
// relationship optional with an explicit inverse, every attribute defaulted — so the
// planned iOS companion is an additive change rather than a migration.

@Model
public final class SummonItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var kindRaw: String = ItemKind.text.rawValue
    public var notes: String = ""

    /// Plaintext body for non-sensitive snippets. Nil once the item is sealed.
    public var bodyText: String?
    /// RTF data for rich snippets, when not sealed.
    public var bodyRTF: Data?
    /// AES-GCM sealed body (text or RTF) for sensitive items.
    public var sealedBody: Data?

    /// Filename inside Blobs/ (plain) or Vault/ (sealed). Empty when there is no blob.
    public var blobFilename: String = ""
    public var blobOriginalName: String = ""
    public var blobExtension: String = ""
    public var blobSealed: Bool = false
    public var byteSize: Int = 0
    public var contentHash: String = ""

    /// OCR / extracted document text, used for search. Sealed for sensitive items,
    /// which is what stops a locked passport scan being found by its contents.
    public var extractedText: String?
    public var sealedExtractedText: Data?

    /// One-line summary, from the on-device model or a heuristic.
    public var summary: String?

    public var isPinned: Bool = false
    public var isSensitive: Bool = false

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var lastUsedAt: Date?
    public var useCount: Int = 0

    public var folder: SummonFolder?
    @Relationship(inverse: \SummonTag.items) public var tags: [SummonTag]? = []
    @Relationship(deleteRule: .cascade, inverse: \AppAffinity.item) public var affinities: [AppAffinity]? = []

    public init(
        id: UUID = UUID(),
        title: String = "",
        kind: ItemKind = .text,
        bodyText: String? = nil,
        folder: SummonFolder? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.bodyText = bodyText
        self.folder = folder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }

    /// Sensitivity is inherited: an item inside a sensitive folder is sensitive.
    public var isEffectivelySensitive: Bool {
        isSensitive || (folder?.isEffectivelySensitive ?? false)
    }

    public var tagNames: [String] {
        (tags ?? []).map(\.name).sorted()
    }

    public var storedBlob: StoredBlob? {
        guard !blobFilename.isEmpty else { return nil }
        return StoredBlob(filename: blobFilename, byteSize: byteSize, contentHash: contentHash,
                          isSealed: blobSealed, fileExtension: blobExtension,
                          originalName: blobOriginalName)
    }

    public func apply(_ blob: StoredBlob) {
        blobFilename = blob.filename
        blobOriginalName = blob.originalName
        blobExtension = blob.fileExtension
        blobSealed = blob.isSealed
        byteSize = blob.byteSize
        contentHash = blob.contentHash
    }
}

@Model
public final class SummonFolder {
    public var id: UUID = UUID()
    public var name: String = ""
    public var symbolName: String = "folder"
    public var colorName: String = "violet"
    public var isSensitive: Bool = false
    public var sortIndex: Int = 0
    public var createdAt: Date = Date()

    public var parent: SummonFolder?
    @Relationship(deleteRule: .cascade, inverse: \SummonFolder.parent)
    public var children: [SummonFolder]? = []
    @Relationship(inverse: \SummonItem.folder)
    public var items: [SummonItem]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "folder",
        colorName: String = "violet",
        isSensitive: Bool = false,
        parent: SummonFolder? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorName = colorName
        self.isSensitive = isSensitive
        self.parent = parent
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    public var isEffectivelySensitive: Bool {
        if isSensitive { return true }
        // Depth-bounded to stay safe against a cycle introduced by a bad drag.
        var node = parent
        var depth = 0
        while let n = node, depth < 32 {
            if n.isSensitive { return true }
            node = n.parent
            depth += 1
        }
        return false
    }

    /// Root-to-leaf names, e.g. ["Clients", "Acme"].
    public var path: [String] {
        var components: [String] = []
        var node: SummonFolder? = self
        var depth = 0
        while let n = node, depth < 32 {
            components.append(n.name)
            node = n.parent
            depth += 1
        }
        return components.reversed()
    }

    public var sortedChildren: [SummonFolder] {
        (children ?? []).sorted {
            $0.sortIndex == $1.sortIndex ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                                         : $0.sortIndex < $1.sortIndex
        }
    }

    /// Every item in this folder and everything nested beneath it.
    public func allItems() -> [SummonItem] {
        var result = items ?? []
        for child in children ?? [] { result.append(contentsOf: child.allItems()) }
        return result
    }
}

@Model
public final class SummonTag {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorName: String = "violet"
    public var createdAt: Date = Date()
    public var items: [SummonItem]? = []

    public init(id: UUID = UUID(), name: String, colorName: String = "violet") {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.createdAt = Date()
    }
}

/// Aggregated "this item was used in this app" counter. Aggregated rather than an
/// event log so it stays bounded, while still powering app-aware ranking.
@Model
public final class AppAffinity {
    public var id: UUID = UUID()
    public var bundleID: String = ""
    public var count: Int = 0
    public var lastUsed: Date = Date()
    public var item: SummonItem?

    public init(bundleID: String, count: Int = 1, item: SummonItem? = nil) {
        self.bundleID = bundleID
        self.count = count
        self.lastUsed = Date()
        self.item = item
    }
}
