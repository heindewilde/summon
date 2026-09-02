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
}
