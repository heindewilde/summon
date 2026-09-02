import Foundation
import Testing
@testable import SummonKit

@Suite("Index build breakdown",
       .enabled(if: ProcessInfo.processInfo.environment["SUMMON_BUILDPROBE"] == "1", "diagnostic"))
struct BuildProbe {
    @Test("What dominates SearchIndex.init?")
    func breakdown() {
        let withBodies = PerfFixture.library(2_000, withBodies: true)
        let noBodies = PerfFixture.library(2_000, withBodies: false)

        func time(_ label: String, _ body: () -> Void) {
            for _ in 0..<3 { body() }
            var best = Double.infinity
            for _ in 0..<8 {
                let s = ContinuousClock.now
                body()
                let e = ContinuousClock.now - s
                best = min(best, Double(e.components.attoseconds) / 1e15)
            }
            print(String(format: "  %-34@ %7.2f ms", label as NSString, best))
        }

        time("full build (with bodies)")   { _ = SearchIndex(items: withBodies) }
        time("full build (no bodies)")     { _ = SearchIndex(items: noBodies) }
        time("bodies only: lowercased+utf8") {
            for i in withBodies { _ = Array(i.searchableText.lowercased().utf8) }
        }
        time("Prepared(title) only") {
            for i in withBodies { _ = FuzzyMatcher.Prepared(i.title) }
        }
        time("Prepared(tags/folder/summary)") {
            for i in withBodies {
                _ = i.tagNames.map(FuzzyMatcher.Prepared.init)
                _ = i.folderPath.isEmpty ? nil : FuzzyMatcher.Prepared(i.folderLabel)
                _ = i.summary.map(FuzzyMatcher.Prepared.init)
            }
        }
    }
}
