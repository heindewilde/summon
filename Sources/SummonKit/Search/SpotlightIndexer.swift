#if canImport(CoreSpotlight)
import CoreSpotlight
import Foundation

/// Your library, findable from the home screen — minus everything you asked to hide.
///
/// The rule is the same one the app already keeps: a locked item is findable by name
/// inside Summon and matches nothing in its contents. Spotlight cannot keep half a
/// promise like that — an index entry lives outside the app, in a database Summon does
/// not control and cannot re-seal — so a sensitive item is not indexed at all, and is
/// actively removed if it ever was.
public enum SpotlightIndexer {
    public static let domain = "com.heindewilde.summon.items"

    /// Which items may be indexed. Public because the test asserts on it directly:
    /// this predicate is the whole security property.
    public static func isIndexable(_ item: ItemSnapshot) -> Bool {
        !item.isSensitive && !item.isLocked
    }

    /// Brings the index in line with the library.
    ///
    /// Indexable items are written; everything else is deleted by identifier rather
    /// than merely skipped, so an item that becomes sensitive — or the whole library
    /// after "Encrypt everything" — leaves Spotlight rather than lingering there with
    /// its old contents.
    public static func reindex(_ items: [ItemSnapshot]) async throws {
        let index = CSSearchableIndex.default()
        let (indexable, excluded) = items.reduce(into: ([ItemSnapshot](), [String]())) { acc, item in
            if isIndexable(item) { acc.0.append(item) } else { acc.1.append(item.id.uuidString) }
        }

        if !excluded.isEmpty {
            try await index.deleteSearchableItems(withIdentifiers: excluded)
        }
        if !indexable.isEmpty {
            try await index.indexSearchableItems(indexable.map(searchable))
        }
    }

    public static func remove(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }

    public static func removeEverything() async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }

    private static func searchable(_ item: ItemSnapshot) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = item.title
        attributes.contentDescription = item.previewLine
        attributes.keywords = item.tagNames
        attributes.contentModificationDate = item.updatedAt
        let searchable = CSSearchableItem(uniqueIdentifier: item.id.uuidString,
                                          domainIdentifier: domain,
                                          attributeSet: attributes)
        return searchable
    }
}
#endif
