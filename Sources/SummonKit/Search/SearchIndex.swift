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

    public let items: [ItemSnapshot]

    /// Per-item text with the lowercasing and bonus tables already computed.
    ///
    /// Built once when the index is built rather than on every keystroke. A short
    /// query is a subsequence of nearly every title, so nearly every item gets fully
    /// scored — doing this work per keystroke is what made large libraries slow.
    struct Entry: Sendable {
        let item: ItemSnapshot
        let title: FuzzyMatcher.Prepared
        let tags: [FuzzyMatcher.Prepared]
        let folder: FuzzyMatcher.Prepared?
        let summary: FuzzyMatcher.Prepared?
        /// Lowercased UTF-8. `String.contains` is Unicode-aware and, measured over a
        /// 2,000-item library, accounted for roughly 98% of a typed search — 19.2ms
        /// against 0.4ms with the bodies removed. Byte search costs almost nothing.
        let bodyBytes: [UInt8]
    }

    private let entries: [Entry]

    public init(items: [ItemSnapshot] = []) {
        self.items = items
        self.entries = items.map { item in
            Entry(
                item: item,
                title: FuzzyMatcher.Prepared(item.title),
                tags: item.tagNames.map(FuzzyMatcher.Prepared.init),
                folder: item.folderPath.isEmpty ? nil : FuzzyMatcher.Prepared(item.folderLabel),
                summary: item.summary.map(FuzzyMatcher.Prepared.init),
                bodyBytes: Array(item.searchableText.lowercased().utf8)
            )
        }
    }

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
        // No text typed: this is the "before you type anything" list — pinned first,
        // then whatever you reach for most, biased by the app you were just in.
        guard !query.text.isEmpty else {
            // Pinning is an explicit instruction, so pinned items form their own
            // section rather than merely getting a boost that heavy use can beat.
            var ranked: [Scored] = []
            ranked.reserveCapacity(min(entries.count, 512))
            for index in entries.indices {
                let item = entries[index].item
                guard SearchIndex.passesFilters(item, query) else { continue }
                let base = SearchIndex.frecency(item, now: now)
                    * SearchIndex.affinityMultiplier(item, frontmostBundleID: frontmostBundleID)
                ranked.append(Scored(index: index, score: base, field: .none))
            }
            ranked.sort { tieBreak($0, $1) }
            let pinned = ranked.filter { entries[$0.index].item.isPinned }
            let rest = ranked.filter { !entries[$0.index].item.isPinned }
            return (pinned + rest).prefix(limit).map {
                SearchResult(item: entries[$0.index].item, score: $0.score,
                             matchField: .none, titlePositions: [])
            }
        }

        // Scoring works over indices and a small value type. `ItemSnapshot` has eight
        // reference-counted fields, so filtering, mapping and sorting arrays of them
        // spends most of its time in ARC rather than in the matcher.
        let scratch = FuzzyMatcher.Scratch()
        let queryChars = FuzzyMatcher.scalars(query.text)
        let queryWords = query.text.lowercased()
            .split(separator: " ")
            .map { Array($0.utf8) }

        var scored: [Scored] = []
        scored.reserveCapacity(min(entries.count, 512))

        for index in entries.indices {
            guard SearchIndex.passesFilters(entries[index].item, query) else { continue }
            guard let hit = score(entries[index], queryChars: queryChars, queryWords: queryWords,
                                  now: now, frontmostBundleID: frontmostBundleID,
                                  scratch: scratch) else { continue }
            scored.append(Scored(index: index, score: hit.score, field: hit.field))
        }

        scored.sort { tieBreak($0, $1) }

        // Positions are only needed for what is shown, so they are recomputed here
        // rather than carried through the sort for every candidate.
        return scored.prefix(limit).map { hit in
            let entry = entries[hit.index]
            var positions: [Int] = []
            if hit.field == .title,
               let m = FuzzyMatcher.match(query: queryChars, in: entry.title, scratch: scratch) {
                positions = m.positions
            }
            return SearchResult(item: entry.item, score: hit.score,
                                matchField: hit.field, titlePositions: positions)
        }
    }

    /// Plain byte substring search. Deliberately not `String.contains`: this runs
    /// against every item that did not already match on a stronger field.
    static func firstIndex(of needle: [UInt8], in haystack: UnsafeBufferPointer<UInt8>) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        let first = needle[0]
        let limit = haystack.count - needle.count
        return needle.withUnsafeBufferPointer { n -> Int? in
            var i = 0
            while i <= limit {
                if haystack[i] == first {
                    var j = 1
                    while j < n.count, haystack[i + j] == n[j] { j += 1 }
                    if j == n.count { return i }
                }
                i += 1
            }
            return nil
        }
    }

    /// A ranked candidate, kept free of reference-counted fields so sorting is cheap.
    private struct Scored {
        var index: Int
        var score: Double
        var field: MatchField
    }

    private func tieBreak(_ a: Scored, _ b: Scored) -> Bool {
        if abs(a.score - b.score) > 0.000_001 { return a.score > b.score }
        let x = entries[a.index].item, y = entries[b.index].item
        if x.isPinned != y.isPinned { return x.isPinned }
        let lx = x.lastUsedAt ?? .distantPast
        let ly = y.lastUsedAt ?? .distantPast
        if lx != ly { return lx > ly }
        return x.title.localizedStandardCompare(y.title) == .orderedAscending
    }

    /// Returns only a score and which field won, so nothing reference-counted is
    /// constructed per candidate.
    func score(
        _ entry: Entry,
        queryChars: [UInt32],
        queryWords: [[UInt8]],
        now: Date,
        frontmostBundleID: String?,
        scratch: FuzzyMatcher.Scratch
    ) -> (score: Double, field: MatchField)? {
        var best = 0.0
        var field = MatchField.none
        if let m = FuzzyMatcher.match(query: queryChars, in: entry.title, scratch: scratch,
                                      needsPositions: false) {
            best = m.score * SearchIndex.weightTitle
            field = .title
        }

        for tag in entry.tags {
            if let m = FuzzyMatcher.match(query: queryChars, in: tag, scratch: scratch,
                                              needsPositions: false) {
                let s = m.score * SearchIndex.weightTag
                if s > best { best = s; field = .tag }
            }
        }

        if let folder = entry.folder,
           let m = FuzzyMatcher.match(query: queryChars, in: folder, scratch: scratch,
                                              needsPositions: false) {
            let s = m.score * SearchIndex.weightFolder
            if s > best { best = s; field = .folder }
        }

        if let summary = entry.summary,
           let m = FuzzyMatcher.match(query: queryChars, in: summary, scratch: scratch,
                                              needsPositions: false) {
            let s = m.score * SearchIndex.weightSummary
            if s > best { best = s; field = .summary }
        }

        // Body text is long, so score it by containment of every query word rather
        // than by subsequence — a scattered subsequence match in a 5,000-word PDF
        // is noise, not a result.
        if !entry.bodyBytes.isEmpty, best < SearchIndex.weightBody {
            entry.bodyBytes.withUnsafeBufferPointer { haystack in
                var firstHit = 0
                var allPresent = true
                for (offset, word) in queryWords.enumerated() {
                    guard let at = SearchIndex.firstIndex(of: word, in: haystack) else {
                        allPresent = false
                        break
                    }
                    if offset == 0 { firstHit = at }
                }
                if allPresent {
                    let positional = 1.0 / (1.0 + Double(firstHit) / 400.0)
                    let s = SearchIndex.weightBody * (0.6 + 0.4 * positional)
                    if s > best { best = s; field = .body }
                }
            }
        }

        guard best > 0 else { return nil }

        let final = best
            * SearchIndex.frecency(entry.item, now: now)
            * SearchIndex.affinityMultiplier(entry.item, frontmostBundleID: frontmostBundleID)
            * (entry.item.isPinned ? 1.25 : 1.0)

        return (final, field)
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
