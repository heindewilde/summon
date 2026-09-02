import Foundation
import Testing
@testable import SummonKit

@Suite("Folder tree")
@MainActor
struct FolderTreeTests {

    private func store() throws -> LibraryStore {
        let paths = LibraryPaths.temporary()
        return try LibraryStore(paths: paths, vault: Vault(paths: paths))
    }

    @Test("A folder can be nested under another")
    func reparent() throws {
        let store = try store()
        let clients = store.createFolder(name: "Clients")
        let decks = store.createFolder(name: "Decks")
        store.moveFolder(decks, under: clients)
        #expect(decks.parent?.id == clients.id)
        #expect(store.children(of: clients).map(\.id) == [decks.id])
    }

    @Test("A folder cannot be dropped into itself")
    func noSelfParent() throws {
        let store = try store()
        let folder = store.createFolder(name: "Loop")
        #expect(!store.canMoveFolder(folder, under: folder))
        store.moveFolder(folder, under: folder)
        #expect(folder.parent == nil)
    }

    @Test("A folder cannot be dropped into its own descendant")
    func noCycle() throws {
        let store = try store()
        let top = store.createFolder(name: "Top")
        let middle = store.createFolder(name: "Middle", parent: top)
        let bottom = store.createFolder(name: "Bottom", parent: middle)

        // Accepting this would detach Top, Middle and Bottom from the tree entirely.
        #expect(!store.canMoveFolder(top, under: bottom))
        store.moveFolder(top, under: bottom)
        #expect(top.parent == nil)
        #expect(bottom.parent?.id == middle.id)
    }

    @Test("Reordering puts a folder before or after a sibling")
    func reorder() throws {
        let store = try store()
        let a = store.createFolder(name: "Alpha")
        let b = store.createFolder(name: "Bravo")
        let c = store.createFolder(name: "Charlie")
        #expect(store.rootFolders().map(\.name) == ["Alpha", "Bravo", "Charlie"])

        store.reorderFolder(c, relativeTo: a, placeAfter: false)
        #expect(store.rootFolders().map(\.name) == ["Charlie", "Alpha", "Bravo"])

        store.reorderFolder(c, relativeTo: b, placeAfter: true)
        #expect(store.rootFolders().map(\.name) == ["Alpha", "Bravo", "Charlie"])
        _ = (a, b)
    }

    @Test("Reordering across levels adopts the sibling's parent")
    func reorderAdoptsParent() throws {
        let store = try store()
        let clients = store.createFolder(name: "Clients")
        let decks = store.createFolder(name: "Decks", parent: clients)
        let loose = store.createFolder(name: "Loose")

        store.reorderFolder(loose, relativeTo: decks, placeAfter: true)
        #expect(loose.parent?.id == clients.id)
        #expect(store.children(of: clients).map(\.name) == ["Decks", "Loose"])
    }

    @Test("Dragging back to the root un-nests")
    func moveToRoot() throws {
        let store = try store()
        let clients = store.createFolder(name: "Clients")
        let decks = store.createFolder(name: "Decks", parent: clients)
        store.moveFolder(decks, under: nil)
        #expect(decks.parent == nil)
        #expect(store.rootFolders().contains { $0.id == decks.id })
    }

    @Test("Order survives a refresh, so it is really persisted")
    func orderPersists() throws {
        let store = try store()
        let a = store.createFolder(name: "Alpha")
        let b = store.createFolder(name: "Bravo")
        store.reorderFolder(b, relativeTo: a, placeAfter: false)
        store.refresh()
        #expect(store.rootFolders().map(\.name) == ["Bravo", "Alpha"])
    }
}
