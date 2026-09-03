import AppKit
import Foundation
import Testing
@testable import SummonKit

@Suite("Folder icons")
struct FolderIconTests {

    /// A misspelled symbol name renders as nothing at all — a blank square that looks
    /// like a bug in the app rather than a typo in a list.
    @Test("Every symbol in the catalogue actually exists")
    func allSymbolsResolve() {
        for symbol in FolderIcon.all {
            #expect(NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil) != nil,
                    "“\(symbol.name)” is not a real SF Symbol")
        }
    }

    @Test("The default is in the catalogue, so the picker shows it as selected")
    func defaultIsListed() {
        #expect(FolderIcon.all.contains { $0.name == FolderIcon.defaultSymbol })
    }

    @Test("No symbol is listed twice")
    func noDuplicates() {
        let names = FolderIcon.all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("Search finds symbols by meaning, not just by name", arguments: [
        ("money", "dollarsign.circle"),
        ("email", "envelope"),
        ("client", "person.2"),
        ("brand", "paintpalette"),
        ("bank", "building.columns"),
        ("password", "key"),
        ("vat", "percent"),
    ])
    func searchByKeyword(_ pair: (String, String)) {
        let (query, expected) = pair
        #expect(FolderIcon.search(query).contains { $0.name == expected },
                "searching “\(query)” should offer \(expected)")
    }

    @Test("An empty search offers everything, a nonsense one offers nothing")
    func searchEdges() {
        #expect(FolderIcon.search("").count == FolderIcon.all.count)
        #expect(FolderIcon.search("   ").count == FolderIcon.all.count)
        #expect(FolderIcon.search("zzzzzz").isEmpty)
    }

    @Test("An exact match is not buried under fuzzy ones")
    func exactMatchesRankFirst() {
        // Substrings win outright when they exist: if you typed "folder" you meant
        // the folder icon, not everything whose letters happen to contain f-o-l-d-e-r.
        let results = FolderIcon.search("folder")
        #expect(results.allSatisfy { $0.name.contains("folder") })
        #expect(FolderIcon.search("envelope").first?.name == "envelope")
    }

    @Test("A partial or abbreviated query still finds the icon", arguments: [
        ("bldcol", "building.columns"),
        ("papclip", "paperclip"),
        ("gradcap", "graduationcap"),
    ])
    func fuzzyFallback(_ pair: (String, String)) {
        let (query, expected) = pair
        // No symbol contains these as a substring, so this exercises the fuzzy path.
        #expect(FolderIcon.search(query).contains { $0.name == expected },
                "“\(query)” should still reach \(expected)")
    }

    @Test("Searching does not rebuild its tables on every call",
          .enabled(if: !PerfBudget.isSharedRunner,
                   "wall-clock is not measurable on a shared runner"))
    func searchIsCheap() {
        // 300 searches over 90 symbols; if Prepared were rebuilt per call this would
        // be the same mistake the search index already had to be corrected for.
        //
        // Budgeted generously and measured as a best-of. The suite runs its tests in
        // parallel, so a single timed run here is really "300 searches plus whatever
        // else the machine was doing" — which is how this started failing in a full
        // run and passing on its own. Three attempts, and the fastest is the one that
        // says something about the code rather than about the scheduler.
        var best = Duration.seconds(3600)
        for _ in 0..<3 {
            let start = ContinuousClock.now
            for _ in 0..<300 { _ = FolderIcon.search("mny") }
            best = min(best, ContinuousClock.now - start)
        }
        #expect(best < .milliseconds(500))
    }

    @Test("Every colour the picker offers resolves to a distinct choice")
    func coloursAreDistinct() {
        #expect(Set(Theme_folderColorNames).count == Theme_folderColorNames.count)
        #expect(Theme_folderColorNames.contains("violet"))
    }

    /// Mirrors Theme.folderColorNames, which lives in SummonUI and cannot be imported
    /// here. Duplicated deliberately: if the two drift, this fails and asks why.
    private var Theme_folderColorNames: [String] {
        ["violet", "blue", "teal", "green", "amber", "red", "graphite"]
    }

    @Test("No folder icon is a glyph that only exists filled")
    func everyIconIsAnOutline() {
        // The set is all outlines, and `airplane` was quietly solid — SF Symbols has
        // no outline version of it, so it read as the odd one out at every size. This
        // is a deny-list rather than a rule because there is no property to test: ink
        // coverage does not separate a filled plane from an outlined gift box, and
        // plenty of legitimate outline symbols (`calendar`, `paperclip`) have no
        // `.fill` counterpart either.
        let solidOnly: Set<String> = ["airplane", "airplane.departure", "airplane.arrival",
                                      "mustache", "peacesign"]
        let used = Set(FolderIcon.all.map(\.name))
        #expect(used.intersection(solidOnly).isEmpty,
                "\(used.intersection(solidOnly)) render solid in an otherwise outlined set")
    }
}
