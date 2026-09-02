import Foundation

public enum MatchField: String, Sendable, Equatable {
    case title, tag, folder, summary, body, none
}

public struct SearchResult: Sendable, Identifiable, Equatable {
    public var item: ItemSnapshot
    public var score: Double
    public var matchField: MatchField
    /// Character positions in the title that matched, for highlighting.
    public var titlePositions: [Int]

    public var id: UUID { item.id }
}

/// Ranks a snapshot set. Pure and deterministic — no store, no clock beyond what
/// the caller passes in — so every scoring rule below is directly testable.
public struct SearchIndex: Sendable {

    // Field weights: a title hit should always beat the same text buried in a body.
    private static let weightTitle = 1.00
    private static let weightTag = 0.78
    private static let weightFolder = 0.60
    private static let weightSummary = 0.52
    private static let weightBody = 0.45

    /// Half-life for the recency term, in days.
    public static let recencyHalfLifeDays = 14.0

    public var items: [ItemSnapshot]

    public init(items: [ItemSnapshot] = []) { self.items = items }

    // MARK: - Ranking components

    /// 1.0 for something used moments ago, decaying by half every two weeks.
    public static func recency(lastUsedAt: Date?, now: Date) -> Double {
        guard let lastUsedAt else { return 0 }
        let days = max(0, now.timeIntervalSince(lastUsedAt) / 86_400)
        return pow(0.5, days / recencyHalfLifeDays)
    }

    /// Frequency × recency. Never zero, so a brand-new item can still surface.
    public static func frecency(_ item: ItemSnapshot, now: Date) -> Double {
        1.0 + 0.8 * log1p(Double(item.useCount)) + 1.2 * recency(lastUsedAt: item.lastUsedAt, now: now)
    }

    /// Boost for items this person has used before in the app they are in right now.
    public static func affinityMultiplier(_ item: ItemSnapshot, frontmostBundleID: String?) -> Double {
        guard let bundle = frontmostBundleID, let count = item.affinity[bundle], count > 0 else { return 1 }
        return 1 + 0.45 * min(1, log1p(Double(count)) / log1p(10))
    }

    // MARK: - Filtering

    public static func passesFilters(_ item: ItemSnapshot, _ query: Query) -> Bool {
        if !query.kinds.isEmpty && !query.kinds.contains(item.kind) { return false }
        if query.pinnedOnly && !item.isPinned { return false }
        if query.sensitiveOnly && !item.isSensitive { return false }
        for tag in query.tags {
            if !item.tagNames.contains(where: { $0.lowercased() == tag }) { return false }
        }
        if let folder = query.folder?.lowercased() {
            let matches = item.folderPath.contains { $0.lowercased().hasPrefix(folder) }
            if !matches { return false }
        }
        return true
    }

    // MARK: - Search

    public func search(_ raw: String, frontmostBundleID: String? = nil, now: Date = Date(), limit: Int = 60) -> [SearchResult] {
        search(query: Query.parse(raw), frontmostBundleID: frontmostBundleID, now: now, limit: limit)
    }

    public func search(query: Query, frontmostBundleID: String? = nil, now: Date = Date(), limit: Int = 60) -> [SearchResult] {
        let candidates = items.filter { SearchIndex.passesFilters($0, query) }

        // No text typed: this is the "before you type anything" list — pinned first,
        // then whatever you reach for most, biased by the app you were just in.
        guard !query.text.isEmpty else {
            // Pinning is an explicit instruction, so pinned items form their own
            // section rather than merely getting a boost that heavy use can beat.
            let scored = candidates.map { item -> SearchResult in
                let base = SearchIndex.frecency(item, now: now)
                    * SearchIndex.affinityMultiplier(item, frontmostBundleID: frontmostBundleID)
                return SearchResult(item: item, score: base, matchField: .none, titlePositions: [])
            }
            let pinned = scored.filter { $0.item.isPinned }.sorted(by: SearchIndex.tieBreak)
            let rest = scored.filter { !$0.item.isPinned }.sorted(by: SearchIndex.tieBreak)
            return Array((pinned + rest).prefix(limit))
        }

        var results: [SearchResult] = []
        results.reserveCapacity(candidates.count)

        for item in candidates {
            guard let scored = SearchIndex.score(item, text: query.text, now: now, frontmostBundleID: frontmostBundleID) else { continue }
            results.append(scored)
        }

        return Array(results.sorted(by: SearchIndex.tieBreak).prefix(limit))
    }

    static func score(_ item: ItemSnapshot, text: String, now: Date, frontmostBundleID: String?) -> SearchResult? {
        var best = 0.0
        var field = MatchField.none
        var positions: [Int] = []

        if let m = FuzzyMatcher.match(query: text, in: item.title) {
            best = m.score * weightTitle
            field = .title
            positions = m.positions
        }

        for tag in item.tagNames {
            if let m = FuzzyMatcher.match(query: text, in: tag) {
                let s = m.score * weightTag
                if s > best { best = s; field = .tag }
            }
        }

        if !item.folderPath.isEmpty, let m = FuzzyMatcher.match(query: text, in: item.folderLabel) {
            let s = m.score * weightFolder
            if s > best { best = s; field = .folder }
        }

        if let summary = item.summary, let m = FuzzyMatcher.match(query: text, in: summary) {
            let s = m.score * weightSummary
            if s > best { best = s; field = .summary }
        }

        // Body text is long, so score it by containment of every query word rather
        // than by subsequence — a scattered subsequence match in a 5,000-word PDF
        // is noise, not a result.
        if !item.searchableText.isEmpty, best < weightBody {
            let words = text.split(separator: " ").map(String.init)
            let haystack = item.searchableText.lowercased()
            let allPresent = words.allSatisfy { haystack.contains($0.lowercased()) }
            if allPresent {
                let firstHit = haystack.range(of: words.first?.lowercased() ?? "")
                    .map { haystack.distance(from: haystack.startIndex, to: $0.lowerBound) } ?? 0
                let positional = 1.0 / (1.0 + Double(firstHit) / 400.0)
                let s = weightBody * (0.6 + 0.4 * positional)
                if s > best { best = s; field = .body }
            }
        }

        guard best > 0 else { return nil }

        let final = best
            * SearchIndex.frecency(item, now: now)
            * SearchIndex.affinityMultiplier(item, frontmostBundleID: frontmostBundleID)
            * (item.isPinned ? 1.25 : 1.0)

        return SearchResult(item: item, score: final, matchField: field,
                            titlePositions: field == .title ? positions : [])
    }

    /// Deterministic ordering: score, then pinned, then recency, then title.
    static func tieBreak(_ a: SearchResult, _ b: SearchResult) -> Bool {
        if abs(a.score - b.score) > 0.000_001 { return a.score > b.score }
        if a.item.isPinned != b.item.isPinned { return a.item.isPinned }
        let la = a.item.lastUsedAt ?? .distantPast
        let lb = b.item.lastUsedAt ?? .distantPast
        if la != lb { return la > lb }
        return a.item.title.localizedStandardCompare(b.item.title) == .orderedAscending
    }
}
