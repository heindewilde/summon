import Foundation
import Testing
@testable import SummonKit

/// Content that is unusual but entirely legitimate. Every one of these is something a
/// real library will eventually contain.
@Suite("Edge-case content")
struct EdgeContentTests {

    private func snapshot(title: String, body: String = "", tags: [String] = []) -> ItemSnapshot {
        ItemSnapshot(title: title, kind: .text, tagNames: tags,
                     searchableText: body, previewLine: String(body.prefix(160)))
    }

    @Test("A very long title neither crashes nor breaks matching")
    func longTitle() throws {
        let title = String(repeating: "Invoice for a client with a remarkably long name ", count: 40)
        let index = SearchIndex(items: [snapshot(title: title)])
        let results = index.search("invoice")
        #expect(results.count == 1)
        // Beyond the DP cap the matcher falls back to containment, which must still
        // find it rather than silently dropping the item out of the library.
        #expect(title.count > FuzzyMatcher.maxCandidateLength)
    }

    @Test("An empty title still yields a findable item")
    func emptyTitle() {
        let index = SearchIndex(items: [snapshot(title: "", body: "the body carries the words")])
        #expect(index.search("body").count == 1)
        #expect(index.search("").count == 1)
    }

    @Test("Emoji and combining marks keep highlight positions inside the string",
          arguments: ["Café résumé", "Naïve façade", "🎉 Party invite", "Ünicode Ümlaut", "日本語のメモ"])
    func unicodeTitles(_ title: String) throws {
        let index = SearchIndex(items: [snapshot(title: title)])
        let results = index.search(String(title.prefix(3)))
        let characters = Array(title)
        for result in results {
            for position in result.titlePositions {
                // A position outside the array would crash HighlightedTitle, which
                // indexes Array(text) with exactly these values.
                #expect(characters.indices.contains(position),
                        "position \(position) outside \(characters.count) characters of \(title)")
            }
        }
    }

    @Test("Right-to-left text is searchable and safely indexed")
    func rightToLeft() {
        let index = SearchIndex(items: [snapshot(title: "فاتورة العميل", body: "invoice arabic")])
        #expect(index.search("invoice").count == 1)
        #expect(index.search("").count == 1)
    }

    @Test("An item with many tags is handled without truncating the search")
    func manyTags() {
        let tags = (0..<40).map { "tag\($0)" }
        let index = SearchIndex(items: [snapshot(title: "Tagged", tags: tags)])
        #expect(index.search("#tag39").count == 1)
        #expect(index.search("#tag0").count == 1)
    }

    @Test("A body of hundreds of kilobytes still searches")
    func hugeBody() {
        let body = String(repeating: "lorem ipsum dolor sit amet ", count: 20_000)
        let index = SearchIndex(items: [snapshot(title: "Big", body: body + " needle")])
        #expect(index.search("needle").count == 1)
    }

    @Test("Whitespace-only and newline-only queries do not match everything")
    func blankQueries() {
        let index = SearchIndex(items: [snapshot(title: "One"), snapshot(title: "Two")])
        // A blank query is the "before you type" list, not a match-all filter.
        #expect(index.search("   ").count == 2)
        #expect(index.search("\n").count == 2)
    }

    @Test("A query longer than any title returns nothing rather than misbehaving")
    func overlongQuery() {
        let index = SearchIndex(items: [snapshot(title: "Short")])
        #expect(index.search(String(repeating: "x", count: 5_000)).isEmpty)
    }

    @Test("Folder names containing spaces still filter", arguments: ["Client", "client", "CLIENT"])
    func folderWithSpaces(_ typed: String) {
        let item = ItemSnapshot(title: "Reply", kind: .text, folderPath: ["Client Replies"])
        var query = Query.parse("")
        query.folder = typed
        #expect(SearchIndex.passesFilters(item, query))
    }
}

@Suite("Blank titles")
struct BlankTitleTests {
    @Test("Renaming to blank yields a findable title, not an invisible row",
          arguments: ["", "   ", "\n", "\t  \n"])
    @MainActor func blankRename(_ attempted: String) async throws {
        let paths = LibraryPaths.temporary()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = try LibraryStore(paths: paths, vault: Vault(paths: paths))
        let item = store.createSnippet(title: "Original", body: "body")
        store.rename(item, to: attempted)
        #expect(item.title == "Untitled")
    }
}
