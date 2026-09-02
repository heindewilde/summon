import Foundation
import Testing
@testable import SummonKit

/// Not an assertion of a target, just a measurement, so scaling decisions are made
/// on numbers rather than on a hunch.
@Suite("Performance probe", .enabled(if: ProcessInfo.processInfo.environment["SUMMON_PERF"] == "1", "measurement only"))
struct PerfProbe {
    private func library(_ count: Int, withBodies: Bool = true) -> [ItemSnapshot] {
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

    @Test("Does body-text scanning dominate?")
    func bodyCost() {
        for withBodies in [true, false] {
            let index = SearchIndex(items: library(2_000, withBodies: withBodies))
            let start = ContinuousClock.now
            for _ in 0..<5 { _ = index.search("invoice") }
            let each = (ContinuousClock.now - start) / 5
            print(String(format: "  2000 items  bodies=%@  %7.2f ms",
                         (withBodies ? "yes" : "no ") as NSString,
                         Double(each.components.attoseconds) / 1e15))
        }
    }

    @Test("Search latency across library sizes")
    func measure() {
        for count in [500, 2_000, 10_000, 50_000] {
            let index = SearchIndex(items: library(count))
            for query in ["", "inv", "invoice", "onboarding client"] {
                let start = ContinuousClock.now
                var results = 0
                for _ in 0..<5 { results = index.search(query, frontmostBundleID: "com.apple.mail").count }
                let each = (ContinuousClock.now - start) / 5
                let label = query.isEmpty ? "(empty)" : query
                print(String(format: "  %6d items  %-18@  %7.2f ms  → %d results",
                             count, label as NSString,
                             Double(each.components.attoseconds) / 1e15, results))
            }
        }
    }
}
