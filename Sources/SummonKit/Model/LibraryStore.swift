import AppKit
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// The library: SwiftData for metadata, `FileStore` for bytes, `Vault` for secrets.
///
/// Everything here runs on the main actor and hands `Sendable` snapshots to the
/// search layer, which keeps SwiftData's main-actor models out of concurrent code
/// entirely. Libraries here are hundreds to low thousands of items, so a single
/// context is the right trade for a great deal of avoided complexity.
@MainActor
@Observable
public final class LibraryStore {
    public let paths: LibraryPaths
    public let files: FileStore
    public let vault: Vault

    public private(set) var container: ModelContainer
    public var context: ModelContext { container.mainContext }

    /// Ranking input. Rebuilt whenever the library or the lock state changes.
    public private(set) var snapshots: [ItemSnapshot] = []
    public private(set) var lastError: String?

    /// Called when an operation fails. Set by `AppModel`.
    ///
    /// `lastError` was written in three places and read in none, so a failed save —
    /// the path every edit takes — lost your change with nothing on screen to say so.
    /// A store cannot present anything itself, but it can refuse to fail quietly.
    @ObservationIgnored public var onError: ((String) -> Void)?

    private func report(_ error: any Error, while action: String) {
        let message = error.localizedDescription
        lastError = message
        Log.store.error("\(action) failed: \(message)")
        onError?("\(action) failed — \(message)")
    }

    /// Bumped on every change so views depending on derived data recompute.
    public private(set) var revision: Int = 0

    /// Identity map, rebuilt with the snapshots. Not observed — it is a lookup
    /// accelerator, never a source of view state.
    @ObservationIgnored private var itemsByID: [UUID: SummonItem] = [:]
    @ObservationIgnored private var foldersByID: [UUID: SummonFolder] = [:]

    public init(paths: LibraryPaths, vault: Vault) throws {
        self.paths = paths
        self.files = FileStore(paths: paths)
        self.vault = vault
        paths.createDirectories()

        let schema = Schema([SummonItem.self, SummonFolder.self, SummonTag.self, AppAffinity.self])
        let config = ModelConfiguration(schema: schema, url: paths.storeURL, cloudKitDatabase: .none)
        self.container = try ModelContainer(for: schema, configurations: [config])
        refresh()
    }

    // MARK: - Fetching

    public func allItems() -> [SummonItem] {
        (try? context.fetch(FetchDescriptor<SummonItem>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
    }

    public func item(id: UUID) -> SummonItem? {
        // Was a full sorted fetch of the entire library per lookup, and it is called
        // from payload(for:), template(for:), recordUse, deleteItem and the preview
        // path. `isDeleted` guards a reference held across a save.
        if let cached = itemsByID[id], !cached.isDeleted { return cached }
        guard let found = allItems().first(where: { $0.id == id }) else { return nil }
        itemsByID[found.id] = found
        return found
    }

    public func allFolders() -> [SummonFolder] {
        (try? context.fetch(FetchDescriptor<SummonFolder>())) ?? []
    }

    /// A folder by id, without re-fetching the table.
    ///
    /// The same accelerator `item(id:)` has, and for the same reason: the sidebar,
    /// the title bar and every drop resolve folders by id, and each of those was a
    /// full fetch of the folder table.
    public func folder(id: UUID) -> SummonFolder? {
        if let cached = foldersByID[id], !cached.isDeleted { return cached }
        guard let found = allFolders().first(where: { $0.id == id }) else { return nil }
        foldersByID[found.id] = found
        return found
    }

    public func rootFolders() -> [SummonFolder] { children(of: nil) }

    public func allTags() -> [SummonTag] {
        ((try? context.fetch(FetchDescriptor<SummonTag>())) ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func tagsInUse() -> [SummonTag] {
        allTags().filter { !($0.items ?? []).isEmpty }
    }

    // MARK: - Snapshots

    public func refresh() {
        let key = vault.currentKey
        let items = allItems()
        itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        foldersByID = Dictionary(allFolders().map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        snapshots = items.map { snapshot(for: $0, key: key) }
        revision &+= 1
    }

    public func snapshot(for item: SummonItem, key: VaultKey?) -> ItemSnapshot {
        let sensitive = item.isEffectivelySensitive
        let locked = sensitive && key == nil

        var searchable = ""
        var preview = ""
        // Resolved once and reused below. Resolving again for `hasPlaceholders` meant
        // a second decrypt of every sealed item on every refresh.
        var body = ""

        if locked {
            // Title and tags stay visible; contents do not. This is the line that
            // stops a locked item being found by searching what is inside it.
            preview = "Locked — unlock to view"
        } else {
            body = resolveBodyText(item, key: key) ?? ""
            let extracted = resolveExtractedText(item, key: key) ?? ""
            searchable = [body, extracted].filter { !$0.isEmpty }.joined(separator: "\n")
            preview = previewLine(for: item, body: body)
        }

        var affinity: [String: Int] = [:]
        for a in item.affinities ?? [] { affinity[a.bundleID] = a.count }

        return ItemSnapshot(
            id: item.id,
            title: item.title,
            kind: item.kind,
            tagNames: item.tagNames,
            folderPath: item.folder?.path ?? [],
            folderID: item.folder?.id,
            sortIndex: item.sortIndex,
            summary: locked ? nil : item.summary,
            searchableText: searchable,
            previewLine: preview,
            isPinned: item.isPinned,
            isSensitive: sensitive,
            isLocked: locked,
            hasPlaceholders: item.kind.isTextual && SnippetTemplate.requiresInput(body),
            useCount: item.useCount,
            lastUsedAt: item.lastUsedAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            byteSize: item.byteSize,
            affinity: affinity
        )
    }

    private func previewLine(for item: SummonItem, body: String) -> String {
        if item.kind.isTextual {
            let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
            return String(firstLine.prefix(160))
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
        let name = item.blobOriginalName.isEmpty ? item.blobExtension.uppercased() : item.blobOriginalName
        return "\(name) · \(size)"
    }

    public func resolveBodyText(_ item: SummonItem, key: VaultKey?) -> String? {
        if let sealed = item.sealedBody {
            guard let key else { return nil }
            if item.kind == .richText {
                guard let data = try? key.open(sealed, itemID: item.id) else { return nil }
                return LibraryStore.plainText(fromRTF: data)
            }
            return try? key.openText(sealed, itemID: item.id)
        }
        if item.kind == .richText, let rtf = item.bodyRTF {
            return item.bodyText ?? LibraryStore.plainText(fromRTF: rtf)
        }
        return item.bodyText
    }

    public func resolveExtractedText(_ item: SummonItem, key: VaultKey?) -> String? {
        if let sealed = item.sealedExtractedText {
            guard let key else { return nil }
            return try? key.openText(sealed, itemID: item.id)
        }
        return item.extractedText
    }

    public static func plainText(fromRTF data: Data) -> String { RTF.plainText(from: data) }

    // MARK: - Creating

    @discardableResult
    public func createSnippet(
        title: String,
        body: String,
        rtf: Data? = nil,
        folder: SummonFolder? = nil,
        tags: [String] = [],
        sensitive: Bool = false,
        pinned: Bool = false
    ) -> SummonItem {
        let item = SummonItem(title: title, kind: rtf == nil ? .text : .richText, folder: folder)
        item.sortIndex = nextSortIndex(in: folder)
        item.isPinned = pinned
        item.isSensitive = sensitive
        item.tags = tags.map { resolveTag(named: $0) }
        context.insert(item)

        applyBody(item, plain: body, rtf: rtf)
        save()
        refresh()
        return item
    }

    /// Writes body content, sealing it when the item is sensitive and the vault is open.
    private func applyBody(_ item: SummonItem, plain: String, rtf: Data?) {
        let shouldSeal = item.isEffectivelySensitive
        if shouldSeal, let key = vault.currentKey {
            let payload = rtf ?? Data(plain.utf8)
            item.sealedBody = try? key.seal(payload, itemID: item.id)
            item.bodyText = nil
            item.bodyRTF = nil
        } else {
            item.bodyText = plain
            item.bodyRTF = rtf
            item.sealedBody = nil
        }
        item.byteSize = (rtf ?? Data(plain.utf8)).count
        item.contentHash = FileStore.hash(rtf ?? Data(plain.utf8))
        item.updatedAt = Date()
    }

    /// Updates a plain-text snippet.
    ///
    /// Split from the rich variant on purpose: a single `rtf: Data? = nil` parameter
    /// meant a caller editing a rich snippet silently dropped its formatting by
    /// omitting an argument. Two explicit methods make that mistake unrepresentable.
    public func updateSnippet(_ item: SummonItem, plain: String) {
        applyBody(item, plain: plain, rtf: nil)
        item.kind = .text
        save()
        refresh()
    }

    /// Updates a rich snippet, preserving its formatting.
    public func updateSnippet(_ item: SummonItem, attributed: NSAttributedString) {
        let rtf = RTF.data(from: attributed)
        applyBody(item, plain: attributed.string, rtf: rtf)
        item.kind = rtf == nil ? .text : .richText
        save()
        refresh()
    }

    /// The body as an attributed string, for the rich editor. Nil while locked.
    public func resolveAttributed(_ item: SummonItem, key: VaultKey?) -> NSAttributedString? {
        if let sealed = item.sealedBody {
            guard let key, let data = try? key.open(sealed, itemID: item.id) else { return nil }
            if item.kind == .richText, let attributed = RTF.attributed(from: data) { return attributed }
            return NSAttributedString(string: String(decoding: data, as: UTF8.self))
        }
        if let rtf = item.bodyRTF, let attributed = RTF.attributed(from: rtf) { return attributed }
        if let text = item.bodyText { return NSAttributedString(string: text) }
        return nil
    }

    @discardableResult
    public func importFile(
        at url: URL,
        title: String? = nil,
        folder: SummonFolder? = nil,
        tags: [String] = [],
        sensitive: Bool = false
    ) -> SummonItem? {
        let kind = ItemKind.forFile(at: url)
        let item = SummonItem(title: title ?? url.deletingPathExtension().lastPathComponent,
                              kind: kind, folder: folder)
        item.sortIndex = nextSortIndex(in: folder)
        item.isSensitive = sensitive
        item.tags = tags.map { resolveTag(named: $0) }
        context.insert(item)

        let key = item.isEffectivelySensitive ? vault.currentKey : nil
        do {
            let blob = try files.importFile(at: url, itemID: item.id, key: key)
            item.apply(blob)
        } catch {
            context.delete(item)
            report(error, while: "Import")
            return nil
        }
        save()
        refresh()
        return item
    }

    @discardableResult
    public func importData(
        _ data: Data,
        title: String,
        kind: ItemKind,
        fileExtension: String,
        originalName: String? = nil,
        folder: SummonFolder? = nil,
        tags: [String] = [],
        sensitive: Bool = false
    ) -> SummonItem? {
        let item = SummonItem(title: title, kind: kind, folder: folder)
        item.sortIndex = nextSortIndex(in: folder)
        item.isSensitive = sensitive
        item.tags = tags.map { resolveTag(named: $0) }
        context.insert(item)

        let key = item.isEffectivelySensitive ? vault.currentKey : nil
        do {
            let blob = try files.importData(data, itemID: item.id, fileExtension: fileExtension,
                                            originalName: originalName, key: key)
            item.apply(blob)
        } catch {
            context.delete(item)
            report(error, while: "Import")
            return nil
        }
        save()
        refresh()
        return item
    }

    // MARK: - Mutating

    public func setPinned(_ item: SummonItem, _ pinned: Bool) {
        item.isPinned = pinned
        item.updatedAt = Date()
        save(); refresh()
    }

    public func togglePinned(id: UUID) {
        guard let item = item(id: id) else { return }
        setPinned(item, !item.isPinned)
    }

    public func rename(_ item: SummonItem, to title: String) {
        // An item whose title is empty or blank renders as an invisible row: you
        // cannot see it, identify it, or search for it by name.
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = trimmed.isEmpty ? "Untitled" : trimmed
        item.updatedAt = Date()
        save(); refresh()
    }

    public func setNotes(_ item: SummonItem, _ notes: String) {
        item.notes = notes
        item.updatedAt = Date()
        save(); refresh()
    }

    public func move(_ item: SummonItem, to folder: SummonFolder?) {
        guard item.folder?.id != folder?.id else { return }
        let wasSensitive = item.isEffectivelySensitive
        let origin = item.folder
        item.folder = folder
        // Lands at the end of the destination rather than wherever its old index
        // happened to point, which would otherwise drop it into the middle.
        item.sortIndex = (folder?.items ?? []).map(\.sortIndex).max().map { $0 + 1 } ?? 0
        item.updatedAt = Date()
        // Moving into or out of a sensitive folder changes how the bytes must be stored.
        reconcileSensitivity(item, wasSensitive: wasSensitive)
        renumberItems(in: origin)
        save(); refresh()
    }

    /// Places `item` immediately before or after `sibling`, adopting its folder.
    ///
    /// The list is hand-ordered only inside a folder; everywhere else has its own
    /// rule (recency, use count, rank) and there is no second order to reconcile.
    public func reorderItem(_ item: SummonItem, relativeTo sibling: SummonItem,
                            placeAfter: Bool) {
        guard item.id != sibling.id else { return }
        let destination = sibling.folder
        let movedFolder = item.folder?.id != destination?.id
        let wasSensitive = item.isEffectivelySensitive
        let origin = item.folder

        item.folder = destination
        var ordered = (destination?.items ?? []).filter { $0.id != item.id }
            .sorted { $0.sortIndex == $1.sortIndex ? $0.updatedAt > $1.updatedAt
                                                   : $0.sortIndex < $1.sortIndex }
        let index = ordered.firstIndex { $0.id == sibling.id } ?? ordered.count
        ordered.insert(item, at: placeAfter ? index + 1 : index)
        for (i, entry) in ordered.enumerated() { entry.sortIndex = i }

        if movedFolder {
            item.updatedAt = Date()
            reconcileSensitivity(item, wasSensitive: wasSensitive)
            renumberItems(in: origin)
        }
        save(); refresh()
    }

    /// One past the last item in `folder`, so anything new lands at the bottom
    /// instead of tying with everything else at zero.
    private func nextSortIndex(in folder: SummonFolder?) -> Int {
        (folder?.items ?? []).map(\.sortIndex).max().map { $0 + 1 } ?? 0
    }

    /// Closes the gap an item left behind, so indices stay dense and comparable.
    private func renumberItems(in folder: SummonFolder?) {
        guard let folder else { return }
        for (index, entry) in folder.directItems.enumerated() { entry.sortIndex = index }
    }

    /// Decrypts everything back to plaintext and clears every sensitive mark.
    ///
    /// The step that has to happen before the vault key is thrown away: removing the
    /// key file with content still sealed leaves that content unreadable, with no way
    /// back. Folders are cleared first, so an item does not re-inherit sensitivity
    /// from its parent halfway through.
    ///
    /// Returns how many items were decrypted.
    @discardableResult
    public func clearAllSensitivity() throws -> Int {
        guard vault.isUnlocked else { throw VaultError.locked }
        // Counted up front: clearing a folder decrypts the items inside it, so
        // counting as we go would report only the ones left over afterwards — and
        // this number is what the confirmation told the user would happen.
        let affected = allItems().count { $0.isEffectivelySensitive }

        for folder in allFolders() where folder.isSensitive {
            try setFolderSensitive(folder, false)
        }
        for item in allItems() where item.isSensitive || item.sealedBody != nil || item.blobSealed {
            try setSensitive(item, false)
        }
        save(); refresh()
        return affected
    }

    /// Marks an item sensitive (encrypting it) or not (decrypting it).
    /// Throws when the vault is locked, because we cannot re-key what we cannot read.
    public func setSensitive(_ item: SummonItem, _ sensitive: Bool) throws {
        guard vault.isUnlocked else { throw VaultError.locked }
        let wasSensitive = item.isEffectivelySensitive
        item.isSensitive = sensitive
        item.updatedAt = Date()
        reconcileSensitivity(item, wasSensitive: wasSensitive)
        save(); refresh()
    }

    public func setFolderSensitive(_ folder: SummonFolder, _ sensitive: Bool) throws {
        guard vault.isUnlocked else { throw VaultError.locked }
        let affected = folder.allItems()
        let before = affected.map { $0.isEffectivelySensitive }
        folder.isSensitive = sensitive
        for (item, was) in zip(affected, before) {
            reconcileSensitivity(item, wasSensitive: was)
        }
        save(); refresh()
    }

    /// Brings an item's stored bytes in line with whether it is now sensitive.
    private func reconcileSensitivity(_ item: SummonItem, wasSensitive: Bool) {
        let isNow = item.isEffectivelySensitive
        guard isNow != wasSensitive, let key = vault.currentKey else { return }

        if isNow {
            if let plain = item.bodyText ?? item.bodyRTF.map({ String(decoding: $0, as: UTF8.self) }) {
                let payload = item.bodyRTF ?? Data(plain.utf8)
                item.sealedBody = try? key.seal(payload, itemID: item.id)
                item.bodyText = nil
                item.bodyRTF = nil
            }
            if let extracted = item.extractedText {
                item.sealedExtractedText = try? key.seal(extracted, itemID: item.id)
                item.extractedText = nil
            }
            if let blob = item.storedBlob, let sealed = try? files.seal(blob, itemID: item.id, key: key) {
                item.apply(sealed)
            }
            files.deleteThumbnail(itemID: item.id)
        } else {
            if let sealed = item.sealedBody, let data = try? key.open(sealed, itemID: item.id) {
                if item.kind == .richText {
                    item.bodyRTF = data
                    item.bodyText = LibraryStore.plainText(fromRTF: data)
                } else {
                    item.bodyText = String(decoding: data, as: UTF8.self)
                }
                item.sealedBody = nil
            }
            if let sealed = item.sealedExtractedText {
                item.extractedText = try? key.openText(sealed, itemID: item.id)
                item.sealedExtractedText = nil
            }
            if let blob = item.storedBlob, let plain = try? files.unseal(blob, itemID: item.id, key: key) {
                item.apply(plain)
            }
        }
    }

    public func delete(_ item: SummonItem) {
        if let blob = item.storedBlob { files.delete(blob) }
        files.deleteThumbnail(itemID: item.id)
        context.delete(item)
        save(); refresh()
    }

    public func delete(ids: [UUID]) {
        let set = Set(ids)
        for item in allItems() where set.contains(item.id) {
            if let blob = item.storedBlob { files.delete(blob) }
            files.deleteThumbnail(itemID: item.id)
            context.delete(item)
        }
        save(); refresh()
    }

    // MARK: - Usage tracking

    /// Records that an item was used, optionally while a particular app was frontmost.
    public func recordUse(id: UUID, inApp bundleID: String?) {
        guard let item = item(id: id) else { return }
        item.useCount += 1
        item.lastUsedAt = Date()

        if let bundleID, !bundleID.isEmpty, bundleID != "com.heindewilde.summon" {
            if let existing = (item.affinities ?? []).first(where: { $0.bundleID == bundleID }) {
                existing.count += 1
                existing.lastUsed = Date()
            } else {
                let affinity = AppAffinity(bundleID: bundleID, item: item)
                context.insert(affinity)
            }
        }
        save(); refresh()
    }

    // MARK: - Folders and tags

    @discardableResult
    public func createFolder(
        name: String,
        parent: SummonFolder? = nil,
        symbolName: String = "folder",
        colorName: String = "violet",
        sensitive: Bool = false
    ) -> SummonFolder {
        let siblings = parent.map { $0.children ?? [] } ?? rootFolders()
        let folder = SummonFolder(name: name, symbolName: symbolName, colorName: colorName,
                                  isSensitive: sensitive, parent: parent,
                                  sortIndex: (siblings.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(folder)
        save(); refresh()
        return folder
    }

    public func setFolderIcon(_ folder: SummonFolder, symbolName: String, colorName: String) {
        folder.symbolName = symbolName
        folder.colorName = colorName
        save(); refresh()
    }

    public func renameFolder(_ folder: SummonFolder, to name: String) {
        folder.name = name
        save(); refresh()
    }

    /// Deletes a folder. Items inside are moved to the parent rather than destroyed —
    /// losing a client's contract because you tidied a folder would be unforgivable.
    public func deleteFolder(_ folder: SummonFolder, keepingItems: Bool = true) {
        if keepingItems {
            for item in folder.items ?? [] { item.folder = folder.parent }
            for child in folder.children ?? [] { child.parent = folder.parent }
        }
        context.delete(folder)
        save(); refresh()
    }

    /// Would moving `folder` under `parent` create a cycle?
    ///
    /// Dropping a folder into its own descendant would detach the whole subtree from
    /// the tree and leave it unreachable, so this is checked before every move — and
    /// the sidebar uses it to refuse the drop rather than accept it and lose things.
    public func canMoveFolder(_ folder: SummonFolder, under parent: SummonFolder?) -> Bool {
        guard parent?.id != folder.id else { return false }
        var node = parent
        var depth = 0
        while let current = node, depth < 64 {
            if current.id == folder.id { return false }
            node = current.parent
            depth += 1
        }
        return true
    }

    public func moveFolder(_ folder: SummonFolder, under parent: SummonFolder?) {
        guard canMoveFolder(folder, under: parent) else { return }
        folder.parent = parent
        renumber(children(of: parent))
        save(); refresh()
    }

    /// Places `folder` immediately before or after `sibling`, adopting its parent.
    ///
    /// `sortIndex` has existed on the model since the first commit and nothing has
    /// ever written to it, so folder order was whatever name sorting produced.
    public func reorderFolder(_ folder: SummonFolder, relativeTo sibling: SummonFolder,
                              placeAfter: Bool) {
        guard folder.id != sibling.id else { return }
        let parent = sibling.parent
        guard canMoveFolder(folder, under: parent) else { return }

        folder.parent = parent
        var ordered = children(of: parent).filter { $0.id != folder.id }
        let index = ordered.firstIndex { $0.id == sibling.id } ?? ordered.count
        ordered.insert(folder, at: placeAfter ? index + 1 : index)
        renumber(ordered)
        save(); refresh()
    }

    /// Siblings in the order they are displayed.
    public func children(of parent: SummonFolder?) -> [SummonFolder] {
        let all = parent.map { $0.children ?? [] } ?? allFolders().filter { $0.parent == nil }
        return all.sorted {
            $0.sortIndex == $1.sortIndex
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.sortIndex < $1.sortIndex
        }
    }

    private func renumber(_ folders: [SummonFolder]) {
        for (index, folder) in folders.enumerated() { folder.sortIndex = index }
    }

    @discardableResult
    public func resolveTag(named raw: String) -> SummonTag {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = allTags().first(where: { $0.name == name }) { return existing }
        let tag = SummonTag(name: name)
        context.insert(tag)
        return tag
    }

    public func setTags(_ item: SummonItem, names: [String]) {
        let unique = Array(Set(names.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }))
            .filter { !$0.isEmpty }
        item.tags = unique.map { resolveTag(named: $0) }
        item.updatedAt = Date()
        save(); refresh()
    }

    /// Renames a tag everywhere it is used.
    ///
    /// Renaming onto a name that already exists *merges* rather than creating two tags
    /// that look identical in the sidebar — which is what a plain rename would do,
    /// since nothing stops two rows sharing a name.
    ///
    /// Returns false when the name is empty or unchanged.
    @discardableResult
    public func renameTag(_ tag: SummonTag, to raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, name != tag.name else { return false }

        if let existing = allTags().first(where: { $0.name == name && $0.id != tag.id }) {
            for item in tag.items ?? [] {
                var names = Set(item.tagNames)
                names.remove(tag.name)
                names.insert(name)
                item.tags = names.map { resolveTag(named: $0) }
                item.updatedAt = Date()
            }
            context.delete(tag)
            _ = existing
        } else {
            tag.name = name
            for item in tag.items ?? [] { item.updatedAt = Date() }
        }
        save(); refresh()
        return true
    }

    /// Removes a tag from every item and deletes it. The items themselves are
    /// untouched — a tag is a label, not a container.
    public func deleteTag(_ tag: SummonTag) {
        for item in tag.items ?? [] {
            item.tags = (item.tags ?? []).filter { $0.id != tag.id }
            item.updatedAt = Date()
        }
        context.delete(tag)
        save(); refresh()
    }

    public func pruneUnusedTags() {
        for tag in allTags() where (tag.items ?? []).isEmpty {
            context.delete(tag)
        }
        save()
    }

    // MARK: - Payload resolution

    /// Everything needed to put an item on the pasteboard. Nil when locked.
    public func payload(for id: UUID, fieldValues: [String: String] = [:], clipboard: String = "") -> InsertPayload? {
        guard let item = item(id: id) else { return nil }
        let key = vault.currentKey
        if item.isEffectivelySensitive && key == nil { return nil }

        switch item.kind {
        case .text, .richText:
            guard let body = resolveBodyText(item, key: key) else { return nil }
            let rendered = SnippetTemplate.parse(body).render(
                values: fieldValues,
                context: RenderContext(clipboard: clipboard)
            )
            var rtf: Data?
            if item.kind == .richText {
                if let sealed = item.sealedBody, let key {
                    rtf = try? key.open(sealed, itemID: item.id)
                } else {
                    rtf = item.bodyRTF
                }
                // A rich snippet with placeholders is rendered as plain text, since
                // splicing values into RTF runs would corrupt the formatting.
                if SnippetTemplate.parse(body).hasPlaceholders { rtf = nil }
            }
            return InsertPayload(plainText: rendered.text, rtf: rtf,
                                 cursorOffsetFromEnd: rendered.cursorOffsetFromEnd)

        case .image:
            guard let blob = item.storedBlob else { return nil }
            let data = try? files.read(blob, itemID: item.id, key: key)
            let url = try? files.materialize(blob, itemID: item.id, key: key)
            return InsertPayload(fileURL: url, imageData: data)

        case .document, .file:
            guard let blob = item.storedBlob,
                  let url = try? files.materialize(blob, itemID: item.id, key: key) else { return nil }
            return InsertPayload(fileURL: url)
        }
    }

    /// The template for an item that needs filling in before it can be inserted.
    public func template(for id: UUID) -> SnippetTemplate? {
        guard let item = item(id: id), item.kind.isTextual else { return nil }
        guard let body = resolveBodyText(item, key: vault.currentKey) else { return nil }
        let template = SnippetTemplate.parse(body)
        return template.requiresInput ? template : nil
    }

    // MARK: - Persistence

    public func save() {
        do {
            try context.save()
        } catch {
            report(error, while: "Save")
        }
    }

    public var isEmpty: Bool { snapshots.isEmpty }
}
