import Foundation
import Testing
@testable import SummonKit

@MainActor
private func makeStore() throws -> (LibraryStore, Vault, LibraryPaths) {
    let paths = LibraryPaths.temporary()
    let vault = Vault(paths: paths)
    let store = try LibraryStore(paths: paths, vault: vault)
    return (store, vault, paths)
}

@Suite("File store")
struct FileStoreTests {
    @Test("An imported file is copied into the library and hashed")
    func importCopies() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let store = FileStore(paths: paths)

        let source = paths.root.appending(path: "original.txt")
        let payload = Data("client proposal".utf8)
        try payload.write(to: source)

        let id = UUID()
        let blob = try store.importFile(at: source, itemID: id, key: nil)

        #expect(blob.byteSize == payload.count)
        #expect(blob.contentHash == FileStore.hash(payload))
        #expect(blob.isSealed == false)
        #expect(FileManager.default.fileExists(atPath: store.location(of: blob).path))

        // The original can vanish without breaking the item — the point of copying.
        try FileManager.default.removeItem(at: source)
        #expect(try store.read(blob, itemID: id, key: nil) == payload)
    }

    @Test("A sealed blob is unreadable on disk and needs the key")
    func sealedBlobIsOpaque() async throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let store = FileStore(paths: paths)
        let key = VaultKey.generate()
        let id = UUID()
        let secret = Data("passport number NLD1234567".utf8)

        let blob = try store.importData(secret, itemID: id, fileExtension: "txt", key: key)
        #expect(blob.isSealed)

        let onDisk = try Data(contentsOf: store.location(of: blob))
        #expect(onDisk != secret)
        #expect(!String(decoding: onDisk, as: UTF8.self).contains("NLD1234567"))

        await #expect(throws: FileStoreError.self) { _ = try store.read(blob, itemID: id, key: nil) }
        #expect(try store.read(blob, itemID: id, key: key) == secret)
    }

    @Test("Sealing and unsealing round-trips and moves the file between folders")
    func sealUnsealRoundTrip() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let store = FileStore(paths: paths)
        let key = VaultKey.generate()
        let id = UUID()
        let payload = Data("contract".utf8)

        let plain = try store.importData(payload, itemID: id, fileExtension: "txt", key: nil)
        let plainURL = store.location(of: plain)

        let sealed = try store.seal(plain, itemID: id, key: key)
        #expect(sealed.isSealed)
        #expect(!FileManager.default.fileExists(atPath: plainURL.path))
        #expect(try store.read(sealed, itemID: id, key: key) == payload)

        let unsealed = try store.unseal(sealed, itemID: id, key: key)
        #expect(!unsealed.isSealed)
        #expect(try store.read(unsealed, itemID: id, key: nil) == payload)
    }

    @Test("Materialising a sealed blob writes a private scratch copy")
    func materializeSealed() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy(); FileStore.clearScratch() }
        let store = FileStore(paths: paths)
        let key = VaultKey.generate()
        let id = UUID()

        let blob = try store.importData(Data("report".utf8), itemID: id,
                                        fileExtension: "txt", originalName: "Report.txt", key: key)
        let url = try store.materialize(blob, itemID: id, key: key)
        #expect(url.lastPathComponent == "Report.txt")
        #expect(try Data(contentsOf: url) == Data("report".utf8))

        // Readable only by its owner, and from the moment it exists. It used to be
        // written and then chmod'd, which left decrypted content at the process umask
        // for the moment in between.
        let mode = try #require(
            try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        #expect(mode.int16Value == 0o600)

        FileStore.clearScratch()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("Library store")
@MainActor
struct LibraryStoreTests {
    @Test("A snippet is created with a searchable snapshot")
    func createSnippet() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        store.createSnippet(title: "Invoice reply", body: "Payment terms are 30 days.")
        #expect(store.snapshots.count == 1)

        let snapshot = try #require(store.snapshots.first)
        #expect(snapshot.title == "Invoice reply")
        #expect(snapshot.searchableText.contains("30 days"))
        #expect(!snapshot.isSensitive)
        #expect(!snapshot.isLocked)
    }

    @Test("Folders nest, and a path reads root to leaf")
    func folderNesting() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let clients = store.createFolder(name: "Clients")
        let acme = store.createFolder(name: "Acme", parent: clients)
        store.createSnippet(title: "Kickoff note", body: "welcome", folder: acme)

        #expect(acme.path == ["Clients", "Acme"])
        #expect(clients.allItems().count == 1)
        #expect(store.snapshots.first?.folderPath == ["Clients", "Acme"])
    }

    @Test("Sensitivity is inherited from an ancestor folder")
    func sensitivityInheritance() async throws {
        let (store, vault, paths) = try makeStore()
        defer { paths.destroy() }
        try await vault.setUpPIN("4829")

        let personal = store.createFolder(name: "Personal", sensitive: true)
        let ids = store.createFolder(name: "IDs", parent: personal)
        let item = store.createSnippet(title: "Passport number", body: "NLD1234567", folder: ids)

        #expect(ids.isEffectivelySensitive)
        #expect(item.isEffectivelySensitive)
    }

    @Test("Marking an item sensitive encrypts its body and locking hides the contents")
    func sensitiveItemEncrypts() async throws {
        let (store, vault, paths) = try makeStore()
        defer { paths.destroy() }
        try await vault.setUpPIN("4829")

        let item = store.createSnippet(title: "Passport number", body: "NLD1234567")
        try store.setSensitive(item, true)

        #expect(item.bodyText == nil)
        #expect(item.sealedBody != nil)

        // Unlocked: contents readable and searchable.
        var snapshot = try #require(store.snapshots.first)
        #expect(!snapshot.isLocked)
        #expect(snapshot.searchableText.contains("NLD1234567"))

        // Locked: the title survives, the contents do not.
        vault.lock()
        store.refresh()
        snapshot = try #require(store.snapshots.first)
        #expect(snapshot.isLocked)
        #expect(snapshot.title == "Passport number")
        #expect(snapshot.searchableText.isEmpty)
        #expect(store.payload(for: item.id) == nil)
    }

    @Test("Removing sensitivity decrypts the body back to plaintext")
    func desensitizeDecrypts() async throws {
        let (store, vault, paths) = try makeStore()
        defer { paths.destroy() }
        try await vault.setUpPIN("4829")

        let item = store.createSnippet(title: "Bank details", body: "IBAN NL91 ABNA")
        try store.setSensitive(item, true)
        try store.setSensitive(item, false)

        #expect(item.sealedBody == nil)
        #expect(item.bodyText == "IBAN NL91 ABNA")
    }

    @Test("Sensitivity cannot be changed while the vault is locked")
    func cannotEncryptWhileLocked() async throws {
        let (store, vault, paths) = try makeStore()
        defer { paths.destroy() }
        try await vault.setUpPIN("4829")
        let item = store.createSnippet(title: "Thing", body: "body")
        vault.lock()

        #expect(throws: VaultError.locked) { try store.setSensitive(item, true) }
    }

    @Test("Using an item records frequency and per-app affinity")
    func usageTracking() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }
        let item = store.createSnippet(title: "Reply", body: "Hello")

        store.recordUse(id: item.id, inApp: "com.apple.mail")
        store.recordUse(id: item.id, inApp: "com.apple.mail")
        store.recordUse(id: item.id, inApp: "com.apple.Safari")

        let snapshot = try #require(store.snapshots.first)
        #expect(snapshot.useCount == 3)
        #expect(snapshot.lastUsedAt != nil)
        #expect(snapshot.affinity["com.apple.mail"] == 2)
        #expect(snapshot.affinity["com.apple.Safari"] == 1)
    }

    @Test("Summon never records affinity against itself")
    func ignoresOwnBundle() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }
        let item = store.createSnippet(title: "Reply", body: "Hello")
        store.recordUse(id: item.id, inApp: "com.heindewilde.summon")
        #expect(store.snapshots.first?.affinity.isEmpty == true)
    }

    @Test("Deleting a folder keeps its items, moving them to the parent")
    func deletingFolderKeepsItems() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let parent = store.createFolder(name: "Clients")
        let child = store.createFolder(name: "Acme", parent: parent)
        store.createSnippet(title: "Contract", body: "terms", folder: child)

        store.deleteFolder(child)

        #expect(store.snapshots.count == 1)
        #expect(store.item(id: store.snapshots[0].id)?.folder?.name == "Clients")
    }

    @Test("A folder cannot be made its own descendant")
    func noFolderCycles() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }
        let parent = store.createFolder(name: "A")
        let child = store.createFolder(name: "B", parent: parent)

        store.moveFolder(parent, under: child)
        #expect(parent.parent == nil)
    }

    @Test("Tags are normalised and reused rather than duplicated")
    func tagReuse() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let a = store.createSnippet(title: "One", body: "x", tags: ["Billing"])
        let b = store.createSnippet(title: "Two", body: "y", tags: ["billing", "  BILLING  "])

        #expect(a.tagNames == ["billing"])
        #expect(b.tagNames == ["billing"])
        #expect(store.allTags().count == 1)
    }

    @Test("A payload renders placeholders and reports the caret offset")
    func payloadRendersTemplate() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let item = store.createSnippet(
            title: "Reply",
            body: "Hi {{first_name}},\n\n{{cursor}}\n\nBest"
        )
        let payload = try #require(store.payload(for: item.id, fieldValues: ["first_name": "Marieke"]))
        #expect(payload.plainText?.contains("Hi Marieke,") == true)
        #expect(payload.plainText?.contains("{{") == false)
        #expect(payload.cursorOffsetFromEnd == 6) // "\n\nBest"
    }

    @Test("Only snippets that actually need input report a template")
    func templateOnlyWhenNeeded() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let withField = store.createSnippet(title: "A", body: "Hi {{name}}")
        let autoOnly = store.createSnippet(title: "B", body: "Sent {{date}}")
        let plain = store.createSnippet(title: "C", body: "Nothing special")

        #expect(store.template(for: withField.id) != nil)
        #expect(store.template(for: autoOnly.id) == nil)
        #expect(store.template(for: plain.id) == nil)
    }

    @Test("Deleting an item removes its blob from disk")
    func deleteRemovesBlob() throws {
        let (store, _, paths) = try makeStore()
        defer { paths.destroy() }

        let source = paths.root.appending(path: "logo.png")
        try Data("not really a png".utf8).write(to: source)
        let item = try #require(store.importFile(at: source))
        let blob = try #require(item.storedBlob)
        let url = store.files.location(of: blob)
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.delete(item)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.snapshots.isEmpty)
    }
}

@Suite("Tag management")
@MainActor
struct TagManagementTests {
    private func store() throws -> LibraryStore {
        let paths = LibraryPaths.temporary()
        return try LibraryStore(paths: paths, vault: Vault(paths: paths))
    }

    @Test("Renaming a tag renames it on every item")
    func renameEverywhere() throws {
        let store = try store()
        let a = store.createSnippet(title: "A", body: "…", tags: ["draft"])
        let b = store.createSnippet(title: "B", body: "…", tags: ["draft", "legal"])

        let draft = try #require(store.allTags().first { $0.name == "draft" })
        #expect(store.renameTag(draft, to: "Drafts"))

        #expect(a.tagNames == ["drafts"])
        #expect(b.tagNames == ["drafts", "legal"])
        // Normalised on the way in, like every other tag.
        #expect(store.allTags().map(\.name).sorted() == ["drafts", "legal"])
    }

    @Test("Renaming onto an existing tag merges rather than duplicating")
    func renameMerges() throws {
        let store = try store()
        let a = store.createSnippet(title: "A", body: "…", tags: ["invoice"])
        let b = store.createSnippet(title: "B", body: "…", tags: ["invoices"])

        let plural = try #require(store.allTags().first { $0.name == "invoices" })
        #expect(store.renameTag(plural, to: "invoice"))

        // One tag, on both items — not two rows in the sidebar sharing a name.
        #expect(store.tagsInUse().map(\.name) == ["invoice"])
        #expect(a.tagNames == ["invoice"])
        #expect(b.tagNames == ["invoice"])
    }

    @Test("An empty or unchanged name is refused")
    func renameRefusesNonsense() throws {
        let store = try store()
        store.createSnippet(title: "A", body: "…", tags: ["draft"])
        let draft = try #require(store.allTags().first { $0.name == "draft" })
        #expect(!store.renameTag(draft, to: "   "))
        #expect(!store.renameTag(draft, to: "draft"))
        #expect(draft.name == "draft")
    }

    @Test("Deleting a tag takes it off its items and leaves them alone")
    func deleteTag() throws {
        let store = try store()
        let a = store.createSnippet(title: "A", body: "keep me", tags: ["draft", "legal"])
        let draft = try #require(store.allTags().first { $0.name == "draft" })

        store.deleteTag(draft)
        #expect(a.tagNames == ["legal"])
        // The item survives: a tag is a label, not a container.
        #expect(store.item(id: a.id) != nil)
        #expect(store.allTags().map(\.name) == ["legal"])
    }
}
