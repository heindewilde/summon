import Foundation
import Testing
@testable import SummonKit

/// Filing items into folders, and the hand-made order inside one.
///
/// The bug that started this: dragging an item onto a folder did nothing at all. The
/// drag carried the item's *contents* and no identity, so the sidebar saw a stray
/// file or a piece of text and either re-imported it or ignored it. Identity is now
/// on the drag; these cover what the drop does once it arrives.
@Suite("Item filing")
@MainActor
struct ItemFilingTests {

    private func store() throws -> LibraryStore {
        let paths = LibraryPaths.temporary()
        return try LibraryStore(paths: paths, vault: Vault(paths: paths))
    }

    @Test("A folder lists its own items, not everything nested beneath it")
    func directItemsExcludeDescendants() throws {
        let store = try store()
        let clients = store.createFolder(name: "Clients")
        let acme = store.createFolder(name: "Acme", parent: clients)
        store.createSnippet(title: "Terms", body: "…", folder: clients)
        store.createSnippet(title: "Acme brief", body: "…", folder: acme)

        // Selecting a parent used to absorb its whole subtree, so an item filed two
        // levels down turned up in three different places at once.
        #expect(clients.directItems.map(\.title) == ["Terms"])
        #expect(acme.directItems.map(\.title) == ["Acme brief"])
        // The subtree is still available where it is genuinely the unit — sealing a
        // folder has to reach everything under it.
        #expect(clients.allItems().count == 2)
    }

    @Test("A snapshot carries the folder it is filed in")
    func snapshotCarriesFolder() throws {
        let store = try store()
        let folder = store.createFolder(name: "Invoices")
        let item = store.createSnippet(title: "March", body: "…", folder: folder)

        let snapshot = store.snapshots.first { $0.id == item.id }
        // The path alone could not answer "is this item *in* this folder", which is
        // what the sidebar now needs.
        #expect(snapshot?.folderID == folder.id)
        #expect(snapshot?.folderPath == ["Invoices"])
    }

    @Test("Moving an item into a folder puts it at the end of that folder's order")
    func moveLandsAtTheEnd() throws {
        let store = try store()
        let folder = store.createFolder(name: "Replies")
        let first = store.createSnippet(title: "One", body: "…", folder: folder)
        let second = store.createSnippet(title: "Two", body: "…", folder: folder)
        let loose = store.createSnippet(title: "Three", body: "…")

        store.move(loose, to: folder)
        #expect(folder.directItems.map(\.title) == ["One", "Two", "Three"])
        _ = (first, second)
    }

    @Test("Moving an item out leaves no gap behind")
    func moveOutRenumbers() throws {
        let store = try store()
        let folder = store.createFolder(name: "Replies")
        let a = store.createSnippet(title: "A", body: "…", folder: folder)
        let b = store.createSnippet(title: "B", body: "…", folder: folder)
        let c = store.createSnippet(title: "C", body: "…", folder: folder)

        store.move(b, to: nil)
        // Dense indices, so the next insertion cannot tie with an existing one.
        #expect(folder.directItems.map(\.sortIndex) == [0, 1])
        #expect(folder.directItems.map(\.title) == ["A", "C"])
        _ = (a, c)
    }

    @Test("Reordering puts an item before or after a sibling")
    func reorder() throws {
        let store = try store()
        let folder = store.createFolder(name: "Replies")
        let a = store.createSnippet(title: "Alpha", body: "…", folder: folder)
        let b = store.createSnippet(title: "Bravo", body: "…", folder: folder)
        let c = store.createSnippet(title: "Charlie", body: "…", folder: folder)
        #expect(folder.directItems.map(\.title) == ["Alpha", "Bravo", "Charlie"])

        store.reorderItem(c, relativeTo: a, placeAfter: false)
        #expect(folder.directItems.map(\.title) == ["Charlie", "Alpha", "Bravo"])

        store.reorderItem(c, relativeTo: b, placeAfter: true)
        #expect(folder.directItems.map(\.title) == ["Alpha", "Bravo", "Charlie"])
    }

    @Test("Dropping an item beside one in another folder moves it there too")
    func reorderAdoptsFolder() throws {
        let store = try store()
        let from = store.createFolder(name: "Inbox")
        let to = store.createFolder(name: "Archive")
        let stray = store.createSnippet(title: "Stray", body: "…", folder: from)
        let anchor = store.createSnippet(title: "Anchor", body: "…", folder: to)

        store.reorderItem(stray, relativeTo: anchor, placeAfter: false)
        #expect(stray.folder?.id == to.id)
        #expect(to.directItems.map(\.title) == ["Stray", "Anchor"])
        #expect(from.directItems.isEmpty)
    }

    @Test("An item cannot be reordered against itself")
    func reorderAgainstSelfIsANoOp() throws {
        let store = try store()
        let folder = store.createFolder(name: "Replies")
        let a = store.createSnippet(title: "A", body: "…", folder: folder)
        store.createSnippet(title: "B", body: "…", folder: folder)

        store.reorderItem(a, relativeTo: a, placeAfter: true)
        #expect(folder.directItems.map(\.title) == ["A", "B"])
    }

    @Test("Order survives a refresh, so it is really persisted")
    func orderPersists() throws {
        let store = try store()
        let folder = store.createFolder(name: "Replies")
        let a = store.createSnippet(title: "Alpha", body: "…", folder: folder)
        let b = store.createSnippet(title: "Bravo", body: "…", folder: folder)

        store.reorderItem(b, relativeTo: a, placeAfter: false)
        store.refresh()
        #expect(folder.directItems.map(\.title) == ["Bravo", "Alpha"])
        #expect(store.snapshots.first { $0.id == b.id }?.sortIndex == 0)
    }

    @Test("Moving an item into a sensitive folder encrypts it")
    func movingIntoASensitiveFolderSeals() throws {
        let store = try store()
        try store.vault.setUpPIN("2413")
        let secrets = store.createFolder(name: "Secrets")
        try store.setFolderSensitive(secrets, true)

        let item = store.createSnippet(title: "Bank details", body: "IBAN NL00")
        #expect(item.bodyText != nil)

        store.move(item, to: secrets)
        // Sensitivity is inherited, so the bytes have to be re-keyed on the way in —
        // filing something into a locked folder must not leave it in the clear.
        #expect(item.isEffectivelySensitive)
        #expect(item.bodyText == nil)
        #expect(item.sealedBody != nil)
    }
}
