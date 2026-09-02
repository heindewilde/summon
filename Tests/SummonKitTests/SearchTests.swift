import Foundation
import Testing
@testable import SummonKit

private let now = Date(timeIntervalSince1970: 1_750_000_000)

private func snap(
    _ title: String,
    kind: ItemKind = .text,
    tags: [String] = [],
    folder: [String] = [],
    body: String = "",
    pinned: Bool = false,
    sensitive: Bool = false,
    locked: Bool = false,
    uses: Int = 0,
    lastUsed: Date? = nil,
    affinity: [String: Int] = [:]
) -> ItemSnapshot {
    ItemSnapshot(title: title, kind: kind, tagNames: tags, folderPath: folder,
                 searchableText: body, isPinned: pinned, isSensitive: sensitive,
                 isLocked: locked, useCount: uses, lastUsedAt: lastUsed, affinity: affinity)
}

@Suite("Query parsing")
struct QueryTests {
    @Test("Plain text is left alone")
    func plainText() {
        let q = Query.parse("invoice reminder")
        #expect(q.text == "invoice reminder")
        #expect(!q.hasFilters)
    }

    @Test("A #tag becomes a tag filter and leaves the text")
    func tagFilter() {
        let q = Query.parse("reminder #billing")
        #expect(q.text == "reminder")
        #expect(q.tags == ["billing"])
    }

    @Test("A /folder becomes a folder filter")
    func folderFilter() {
        let q = Query.parse("/Clients acme")
        #expect(q.folder == "Clients")
        #expect(q.text == "acme")
    }

    @Test("Kind tokens filter by type, with or without a trailing term",
          arguments: [("img: logo", ItemKind.image, "logo"),
                      ("pdf:contract", ItemKind.document, "contract"),
                      ("file: keynote", ItemKind.file, "keynote")])
    func kindFilters(raw: String, kind: ItemKind, text: String) {
        let q = Query.parse(raw)
        #expect(q.kinds.contains(kind))
        #expect(q.text == text)
    }

    @Test("txt: covers both plain and rich snippets")
    func textKind() {
        let q = Query.parse("txt: signature")
        #expect(q.kinds == [.text, .richText])
    }

    @Test("Filters combine")
    func combined() {
        let q = Query.parse("pdf: #legal /Clients nda")
        #expect(q.kinds == [.document])
        #expect(q.tags == ["legal"])
        #expect(q.folder == "Clients")
        #expect(q.text == "nda")
        #expect(q.filterChips.contains("#legal"))
    }

    @Test("An empty query is recognised as empty")
    func empty() {
        #expect(Query.parse("").isEmpty)
        #expect(Query.parse("   ").isEmpty)
    }
}

@Suite("Fuzzy matching")
struct FuzzyTests {
    @Test("A non-subsequence does not match at all")
    func noMatch() {
        #expect(FuzzyMatcher.match(query: "zzz", in: "Invoice reminder") == nil)
    }

    @Test("Matched positions point at the right characters")
    func positions() throws {
        let m = try #require(FuzzyMatcher.match(query: "inv", in: "Invoice"))
        #expect(m.positions == [0, 1, 2])
    }

    @Test("A word-start match outranks the same letters mid-word")
    func wordStartWins() throws {
        let prefix = try #require(FuzzyMatcher.match(query: "ir", in: "Invoice Reminder"))
        let buried = try #require(FuzzyMatcher.match(query: "ir", in: "Third Party"))
        #expect(prefix.score > buried.score)
    }

    @Test("Consecutive characters outrank scattered ones")
    func consecutiveWins() throws {
        let tight = try #require(FuzzyMatcher.match(query: "sign", in: "Signature"))
        let loose = try #require(FuzzyMatcher.match(query: "sign", in: "Sending invoices next week"))
        #expect(tight.score > loose.score)
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        #expect(FuzzyMatcher.match(query: "NDA", in: "nda template") != nil)
        #expect(FuzzyMatcher.match(query: "nda", in: "NDA Template") != nil)
    }

    @Test("An exact full-string match scores highest of all")
    func exactWins() throws {
        let exact = try #require(FuzzyMatcher.match(query: "logo", in: "logo"))
        let partial = try #require(FuzzyMatcher.match(query: "logo", in: "logo dark variant"))
        #expect(exact.score > partial.score)
    }

    @Test("An empty query matches everything with a neutral score")
    func emptyQuery() throws {
        let m = try #require(FuzzyMatcher.match(query: "", in: "anything"))
        #expect(m.score == 0)
    }
}

@Suite("Ranking")
struct RankingTests {
    @Test("A title hit outranks the same words buried in a body")
    func titleBeatsBody() throws {
        let index = SearchIndex(items: [
            snap("Onboarding checklist", body: "unrelated"),
            snap("Meeting notes", body: "the onboarding checklist is attached"),
        ])
        let results = index.search("onboarding checklist", now: now)
        #expect(results.count == 2)
        #expect(results.first?.item.title == "Onboarding checklist")
        #expect(results.first?.matchField == .title)
    }

    @Test("Frequently used items rise above equally-matching rare ones")
    func frecencyLifts() throws {
        let index = SearchIndex(items: [
            snap("Invoice reply", uses: 0),
            snap("Invoice reply B", uses: 40, lastUsed: now.addingTimeInterval(-3600)),
        ])
        let results = index.search("invoice", now: now)
        #expect(results.first?.item.title == "Invoice reply B")
    }

    @Test("Recency decays by half every fourteen days")
    func recencyDecay() {
        let fresh = SearchIndex.recency(lastUsedAt: now, now: now)
        let twoWeeks = SearchIndex.recency(lastUsedAt: now.addingTimeInterval(-14 * 86_400), now: now)
        let fourWeeks = SearchIndex.recency(lastUsedAt: now.addingTimeInterval(-28 * 86_400), now: now)
        #expect(abs(fresh - 1.0) < 0.0001)
        #expect(abs(twoWeeks - 0.5) < 0.0001)
        #expect(abs(fourWeeks - 0.25) < 0.0001)
        #expect(SearchIndex.recency(lastUsedAt: nil, now: now) == 0)
    }

    @Test("An item used before in the frontmost app is boosted")
    func appAffinity() throws {
        let items = [
            snap("Reply template A", uses: 5, lastUsed: now, affinity: [:]),
            snap("Reply template B", uses: 5, lastUsed: now, affinity: ["com.apple.mail": 8]),
        ]
        let neutral = SearchIndex(items: items).search("reply", now: now)
        #expect(neutral.first?.item.title == "Reply template A")  // stable tie-break by title

        let inMail = SearchIndex(items: items).search("reply", frontmostBundleID: "com.apple.mail", now: now)
        #expect(inMail.first?.item.title == "Reply template B")
    }

    @Test("Affinity for a different app does not boost")
    func affinityIsPerApp() {
        let item = snap("X", affinity: ["com.apple.mail": 9])
        #expect(SearchIndex.affinityMultiplier(item, frontmostBundleID: "com.apple.Safari") == 1)
        #expect(SearchIndex.affinityMultiplier(item, frontmostBundleID: nil) == 1)
        #expect(SearchIndex.affinityMultiplier(item, frontmostBundleID: "com.apple.mail") > 1)
    }

    @Test("With no query typed, pinned items come first")
    func emptyQueryShowsPinned() {
        let index = SearchIndex(items: [
            snap("Used constantly", uses: 100, lastUsed: now),
            snap("Pinned thing", pinned: true, uses: 1),
        ])
        let results = index.search("", now: now)
        #expect(results.first?.item.title == "Pinned thing")
    }

    @Test("Kind filters exclude other kinds")
    func kindFiltering() {
        let index = SearchIndex(items: [
            snap("Contract", kind: .document),
            snap("Contract snippet", kind: .text),
        ])
        let results = index.search("pdf: contract", now: now)
        #expect(results.count == 1)
        #expect(results.first?.item.kind == .document)
    }

    @Test("Tag filters require the tag")
    func tagFiltering() {
        let index = SearchIndex(items: [
            snap("A", tags: ["billing"]),
            snap("B", tags: ["legal"]),
        ])
        #expect(index.search("#billing", now: now).count == 1)
    }

    @Test("Folder filters match anywhere in the path")
    func folderFiltering() {
        let index = SearchIndex(items: [
            snap("A", folder: ["Clients", "Acme"]),
            snap("B", folder: ["Personal"]),
        ])
        let results = index.search("/Clients", now: now)
        #expect(results.count == 1)
        #expect(results.first?.item.title == "A")
    }

    @Test("A locked item is findable by title but not by its contents")
    func lockedContentNotSearchable() {
        // A locked snapshot carries no searchable text — that is the whole mechanism.
        let locked = snap("Passport scan", kind: .image, body: "", locked: true, uses: 1)
        let index = SearchIndex(items: [locked])

        #expect(index.search("passport", now: now).count == 1)
        #expect(index.search("NLD1234567", now: now).isEmpty)
    }

    @Test("An unlocked equivalent is findable by its contents")
    func unlockedContentSearchable() {
        let unlocked = snap("Passport scan", kind: .image, body: "NLD1234567 surname given names")
        let index = SearchIndex(items: [unlocked])
        #expect(index.search("NLD1234567", now: now).count == 1)
        #expect(index.search("NLD1234567", now: now).first?.matchField == .body)
    }

    @Test("Body matching requires every typed word to be present")
    func bodyRequiresAllWords() {
        let index = SearchIndex(items: [snap("Notes", body: "quarterly revenue figures")])
        #expect(index.search("quarterly revenue", now: now).count == 1)
        #expect(index.search("quarterly expenses", now: now).isEmpty)
    }

    @Test("Results are limited and deterministically ordered")
    func deterministicOrder() {
        let items = (0..<50).map { snap("Item \($0)", uses: 1) }
        let a = SearchIndex(items: items).search("item", now: now, limit: 10)
        let b = SearchIndex(items: items.reversed()).search("item", now: now, limit: 10)
        #expect(a.count == 10)
        #expect(a.map(\.item.title) == b.map(\.item.title))
    }

    @Test("Pinned wins a genuine tie")
    func pinnedTieBreak() {
        let index = SearchIndex(items: [
            snap("Same name", uses: 3, lastUsed: now),
            snap("Same name", pinned: true, uses: 3, lastUsed: now),
        ])
        #expect(index.search("same name", now: now).first?.item.isPinned == true)
    }
}
