import Foundation

/// Owns the lifetime of a `SearchIndex`, so it is built when the library changes
/// rather than on every keystroke.
///
/// `SearchIndex.init` prepares per-item fuzzy tables and a lowercased UTF-8 copy of
/// every body — work whose entire point is that it is paid once. Constructing the
/// index at the call site threw that away silently. This type exists to make that
/// regression impossible to reintroduce without a test failing: `buildCount` counts
/// real constructions, and the suite asserts it stays flat while the library does.
///
/// Deliberately not `@Observable`. `itemsForSidebar()` is called from view bodies,
/// and mutating observable state during a render is how you earn a purple runtime
/// warning and an invalidation loop.
@MainActor
public final class SearchEngine {

    /// Indexes actually constructed since launch. Asserted on in `PerfProbe`.
    public private(set) var buildCount = 0

    private var index = SearchIndex()
    private var builtRevision = -1

    /// A second slot for filtered subsets — the main window's sidebar searches a
    /// different item set from the panel, and sharing one slot would make the two
    /// surfaces evict each other on every switch.
    private var filtered = SearchIndex()
    private var filteredRevision = -1
    private var filteredToken: String?

    public init() {}

    /// The panel's path: the whole library, ranked with app affinity.
    public func search(_ query: String,
                       snapshots: [ItemSnapshot],
                       revision: Int,
                       frontmostBundleID: String? = nil,
                       limit: Int = 60) -> [SearchResult] {
        if revision != builtRevision {
            index = SearchIndex(items: snapshots)
            builtRevision = revision
            buildCount &+= 1
        }
        return index.search(query, frontmostBundleID: frontmostBundleID, limit: limit)
    }

    /// The panel's path, grouped for display.
    public func sections(_ query: Query,
                         snapshots: [ItemSnapshot],
                         revision: Int,
                         frontmostBundleID: String? = nil,
                         frontmostAppName: String? = nil,
                         limit: Int = 60) -> [SearchSection] {
        if revision != builtRevision {
            index = SearchIndex(items: snapshots)
            builtRevision = revision
            buildCount &+= 1
        }
        return index.sections(query: query,
                              frontmostBundleID: frontmostBundleID,
                              frontmostAppName: frontmostAppName,
                              limit: limit)
    }

    /// The main window's path: an already-filtered subset. `token` identifies which
    /// subset, so switching folders rebuilds but typing within one does not.
    public func searchFiltered(_ query: String,
                               snapshots: [ItemSnapshot],
                               revision: Int,
                               token: String,
                               limit: Int = 60) -> [SearchResult] {
        if revision != filteredRevision || token != filteredToken {
            filtered = SearchIndex(items: snapshots)
            filteredRevision = revision
            filteredToken = token
            buildCount &+= 1
        }
        return filtered.search(query, limit: limit)
    }

    /// Drops both caches. The store always bumps `revision` on change, so nothing
    /// needs this today — it exists so a future caller with a genuine reason has a
    /// correct escape hatch instead of inventing a wrong one.
    public func invalidate() {
        builtRevision = -1
        filteredRevision = -1
        filteredToken = nil
    }
}
