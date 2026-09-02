import Foundation
import Testing
@testable import SummonKit

/// Shared fixture and timing helper for the budget suite.
enum PerfFixture {
    static func library(_ count: Int, withBodies: Bool = true) -> [ItemSnapshot] {
        let words = ["invoice", "contract", "onboarding", "reply", "proposal", "meeting",
                     "passport", "logo", "address", "signature", "terms", "quote"]
        return (0..<count).map { i in
            ItemSnapshot(
                title: "\(words[i % words.count].capitalized) \(i) for client \(i % 400)",
                kind: ItemKind.allCases[i % ItemKind.allCases.count],
                tagNames: [words[(i + 3) % words.count]],
                folderPath: ["Clients", "Group \(i % 40)"],
                searchableText: withBodies
                    ? String(repeating: "\(words[(i + 5) % words.count]) body text ", count: 30)
                    : "",
                useCount: i % 25,
                lastUsedAt: Date().addingTimeInterval(-Double(i) * 900)
            )
        }
    }
}

struct Stats {
    var samples: [Double]   // milliseconds

    var best: Double { samples.min() ?? .infinity }
    var median: Double { samples.sorted()[samples.count / 2] }
    var worst: Double { samples.max() ?? .infinity }

    func report(_ label: String, budget: Double) {
        print(String(format: "  %-24@ best %6.2f ms   median %6.2f   worst %6.2f   budget %.0f ms",
                     label as NSString, best, median, worst, budget))
    }
}

enum PerfBudget {
    /// Budgets are asserted on the **minimum**, not the mean or max. Timing noise is
    /// one-sided — the scheduler only ever adds time — so the fastest observed run is
    /// the honest estimator of "this code can run in X". Asserting the max makes the
    /// suite flaky on a loaded machine, and the usual response to a flaky budget is to
    /// raise it, which is exactly how a budget stops meaning anything.
    static func measure(warmup: Int = 3, iterations: Int = 15, _ body: () -> Void) -> Stats {
        for _ in 0..<warmup { body() }
        var samples: [Double] = []
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            body()
            let elapsed = ContinuousClock.now - start
            samples.append(Double(elapsed.components.attoseconds) / 1e15
                           + Double(elapsed.components.seconds) * 1000)
        }
        return Stats(samples: samples)
    }

    /// These numeric loops run 5–20× slower unoptimised. A budget that passes in debug
    /// because it was calibrated for debug asserts nothing at all, so the suite only
    /// runs in release: `swift test -c release`.
    static var isOptimised: Bool {
        var optimised = true
        assert({ optimised = false; return true }())
        return optimised
    }
}

@Suite("Performance budgets",
       .enabled(if: PerfBudget.isOptimised, "budgets are asserted in release: swift test -c release"))
struct PerfBudgetTests {

    @Test("A keystroke re-ranks 2,000 items in under 4ms")
    @MainActor func keystroke() {
        let items = PerfFixture.library(2_000)
        let engine = SearchEngine()
        _ = engine.search("warm", snapshots: items, revision: 1)

        let stats = PerfBudget.measure {
            _ = engine.search("invoice", snapshots: items, revision: 1,
                              frontmostBundleID: "com.apple.mail")
        }
        stats.report("keystroke→results", budget: 4)
        #expect(stats.best < 4.0)
    }

    @Test("The empty-query path — which runs on every panel open — stays under 4ms")
    @MainActor func emptyQuery() {
        let items = PerfFixture.library(2_000)
        let engine = SearchEngine()
        _ = engine.search("", snapshots: items, revision: 1)

        let stats = PerfBudget.measure {
            _ = engine.search("", snapshots: items, revision: 1, frontmostBundleID: "com.apple.mail")
        }
        stats.report("empty query", budget: 4)
        #expect(stats.best < 4.0)
    }

    @Test("Building the index for 2,000 items stays under 25ms")
    func indexBuild() {
        let items = PerfFixture.library(2_000)
        // Inside the loop. Building it outside was the flaw that let the per-keystroke
        // rebuild hide behind a benchmark that looked healthy.
        let stats = PerfBudget.measure(warmup: 2, iterations: 8) {
            _ = SearchIndex(items: items)
        }
        stats.report("index build", budget: 25)
        #expect(stats.best < 25.0)
    }

    @Test("Typing does not rebuild the index")
    @MainActor func typingDoesNotRebuild() {
        let items = PerfFixture.library(500)
        let engine = SearchEngine()
        _ = engine.search("", snapshots: items, revision: 1)
        let after = engine.buildCount

        for query in ["i", "in", "inv", "invo", "invoi", "invoice"] {
            _ = engine.search(query, snapshots: items, revision: 1)
        }

        // The regression this whole refactor exists to prevent: AppModel.runSearch()
        // used to construct a SearchIndex on every keystroke, defeating the doc comment
        // directly above SearchIndex.init.
        #expect(engine.buildCount == after)
        #expect(after == 1)
    }

    @Test("A library change does rebuild the index, exactly once")
    @MainActor func revisionRebuilds() {
        let items = PerfFixture.library(200)
        let engine = SearchEngine()
        _ = engine.search("a", snapshots: items, revision: 1)
        #expect(engine.buildCount == 1)

        _ = engine.search("a", snapshots: items, revision: 2)
        _ = engine.search("b", snapshots: items, revision: 2)
        _ = engine.search("c", snapshots: items, revision: 2)
        #expect(engine.buildCount == 2)
    }

    @Test("The panel and the sidebar do not evict each other")
    @MainActor func twoSlots() {
        let all = PerfFixture.library(200)
        let subset = Array(all.prefix(40))
        let engine = SearchEngine()

        _ = engine.search("a", snapshots: all, revision: 1)
        _ = engine.searchFiltered("a", snapshots: subset, revision: 1, token: "folder:x")
        #expect(engine.buildCount == 2)

        // Alternating between the two surfaces must not rebuild either one.
        for _ in 0..<5 {
            _ = engine.search("b", snapshots: all, revision: 1)
            _ = engine.searchFiltered("b", snapshots: subset, revision: 1, token: "folder:x")
        }
        #expect(engine.buildCount == 2)
    }
}

@Suite("ASCII fast path")
struct ASCIIFastPathTests {

    /// The fast path must be indistinguishable from the Character-based one, or every
    /// ranking test in the suite is testing a different scorer than the app runs.
    @Test("Produces identical tables to the general path", arguments: [
        "Invoice template",
        "invoice",
        "Follow-up reply #2",
        "IBAN NL91 ABNA 0417 1643 00",
        "camelCaseTitle",
        "with.dots:and,commas",
        "under_score-dash/slash",
        "  leading spaces",
        "tabs\tand\nnewlines",
        "123 numbers 456",
        "MiXeD CaSe",
        "",
        "a",
        "/",
    ])
    func matchesGeneralPath(_ text: String) throws {
        let fast = try #require(FuzzyMatcher.asciiTables(text), "expected the ASCII path for \(text)")
        let chars = Array(text)
        #expect(fast.oversized == false)
        #expect(fast.lower == FuzzyMatcher.scalars(chars))
        #expect(fast.bonuses == FuzzyMatcher.characterBonuses(chars))
    }

    @Test("Declines non-ASCII so the general path keeps handling it", arguments: [
        "Café résumé", "naïve", "日本語のタイトル", "emoji 🎉 here", "Ünicode",
    ])
    func declinesNonASCII(_ text: String) {
        #expect(FuzzyMatcher.asciiTables(text) == nil)
    }

    /// Highlight positions index into `Array(text)`, so a multi-scalar grapheme must
    /// not be allowed to shift them.
    @Test("Non-ASCII candidates still align positions with Array(text)")
    func nonASCIIPositionsAlign() throws {
        let text = "Café menu"
        let prepared = FuzzyMatcher.Prepared(text)
        let match = try #require(FuzzyMatcher.match(query: FuzzyMatcher.scalars("menu"),
                                                   in: prepared,
                                                   scratch: FuzzyMatcher.Scratch()))
        let chars = Array(text)
        for position in match.positions { #expect(chars.indices.contains(position)) }
        #expect(match.positions.map { chars[$0] } == ["m", "e", "n", "u"])
    }

    @Test("Oversized candidates still fall back to containment")
    func oversized() {
        let long = String(repeating: "a", count: 600)
        let prepared = FuzzyMatcher.Prepared(long)
        #expect(prepared.lower.isEmpty)
    }
}

@Suite("Result sections")
struct SearchSectionTests {

    private func item(_ title: String, pinned: Bool = false,
                      affinity: [String: Int] = [:], used: Int = 1) -> ItemSnapshot {
        ItemSnapshot(title: title, kind: .text, isPinned: pinned,
                     useCount: used, lastUsedAt: Date(), affinity: affinity)
    }

    @Test("A typed query returns one unlabelled section")
    func typedQueryIsFlat() {
        let index = SearchIndex(items: [item("Invoice"), item("Invoice two")])
        let sections = index.sections("invoice")
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].results.count == 2)
    }

    @Test("The app section appears only once there is real history there")
    func appSectionNeedsHistory() {
        let mail = "com.apple.mail"
        let barely = SearchIndex(items: [item("Reply", affinity: [mail: 2]), item("Other")])
        #expect(barely.sections("", frontmostBundleID: mail, frontmostAppName: "Mail")
                    .contains { $0.title == "In Mail" } == false)

        let habit = SearchIndex(items: [item("Reply", affinity: [mail: 3]), item("Other")])
        let sections = habit.sections("", frontmostBundleID: mail, frontmostAppName: "Mail")
        #expect(sections.first?.title == "In Mail")
        #expect(sections.first?.results.first?.item.title == "Reply")
    }

    @Test("Pinned is its own section, and nothing appears in two sections")
    func noDuplicates() {
        let mail = "com.apple.mail"
        let index = SearchIndex(items: [
            item("Signature", pinned: true, affinity: [mail: 9]),
            item("VAT number", pinned: true),
            item("Headshot"),
        ])
        let sections = index.sections("", frontmostBundleID: mail, frontmostAppName: "Mail")
        let titles = sections.compactMap(\.title)
        #expect(titles == ["In Mail", "Pinned", "Recent"])

        let ids = sections.allResults.map(\.id)
        #expect(Set(ids).count == ids.count, "an item must not appear in two sections")
    }

    @Test("Flattening preserves display order, so ⌘N matches the badge")
    func flatteningOrder() {
        let mail = "com.apple.mail"
        let index = SearchIndex(items: [
            item("Reply", affinity: [mail: 5]),
            item("VAT number", pinned: true),
            item("Headshot"),
        ])
        let sections = index.sections("", frontmostBundleID: mail, frontmostAppName: "Mail")
        #expect(sections.allResults.map(\.item.title) == ["Reply", "VAT number", "Headshot"])
    }

    @Test("With no affinity and nothing pinned there is a single unlabelled section")
    func plainLibrary() {
        let index = SearchIndex(items: [item("One"), item("Two")])
        let sections = index.sections("")
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
    }
}
