import Foundation

/// Turns raw captures into library items, then enriches them in the background.
///
/// Import is deliberately two-phase: the item appears instantly with a usable title,
/// and OCR plus the on-device model fill in the rest a moment later. Waiting on a
/// language model before showing the thing you just dropped would be the wrong trade.
@MainActor
public final class Importer {
    private let store: LibraryStore
    private let intelligence: Intelligence

    public init(store: LibraryStore, intelligence: Intelligence) {
        self.store = store
        self.intelligence = intelligence
    }

    // MARK: - Entry points

    @discardableResult
    public func importFiles(
        _ urls: [URL],
        into folder: SummonFolder? = nil,
        sensitive: Bool = false
    ) async -> [SummonItem] {
        var created: [SummonItem] = []
        for url in urls {
            // A directory dropped on Summon imports its files rather than failing.
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])) ?? []
                created.append(contentsOf: await importFiles(children, into: folder, sensitive: sensitive))
                continue
            }
            guard let item = store.importFile(
                at: url,
                title: Heuristics.title(forFilename: url.lastPathComponent),
                folder: folder,
                sensitive: sensitive
            ) else { continue }
            created.append(item)
        }
        for item in created { await enrich(item, titleWasGiven: false) }
        return created
    }

    @discardableResult
    public func importText(
        _ text: String,
        rtf: Data? = nil,
        title: String? = nil,
        into folder: SummonFolder? = nil,
        tags: [String] = [],
        sensitive: Bool = false
    ) async -> SummonItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = store.createSnippet(
            title: title ?? Heuristics.title(forText: text),
            body: text, rtf: rtf, folder: folder, tags: tags, sensitive: sensitive
        )
        await enrich(item, titleWasGiven: title != nil)
        return item
    }

    @discardableResult
    public func importImage(
        _ data: Data,
        title: String? = nil,
        into folder: SummonFolder? = nil,
        sensitive: Bool = false
    ) async -> SummonItem? {
        let name = title ?? "Image \(Date().formatted(date: .abbreviated, time: .shortened))"
        guard let item = store.importData(data, title: name, kind: .image, fileExtension: "png",
                                          originalName: "\(name).png", folder: folder,
                                          sensitive: sensitive) else { return nil }
        await enrich(item, titleWasGiven: title != nil)
        return item
    }

    @discardableResult
    public func importClipboardEntry(
        _ entry: ClipboardMonitor.Entry,
        into folder: SummonFolder? = nil,
        sensitive: Bool = false
    ) async -> SummonItem? {
        if let url = entry.fileURL {
            return await importFiles([url], into: folder, sensitive: sensitive).first
        }
        if let data = entry.imageData {
            return await importImage(data, title: entry.suggestedTitle, into: folder, sensitive: sensitive)
        }
        if let text = entry.text {
            return await importText(text, rtf: entry.rtf, into: folder, sensitive: sensitive)
        }
        return nil
    }

    @discardableResult
    public func importSelection(
        _ selection: CapturedSelection,
        into folder: SummonFolder? = nil,
        sensitive: Bool = false
    ) async -> [SummonItem] {
        switch selection {
        case .files(let urls):
            return await importFiles(urls, into: folder, sensitive: sensitive)
        case .text(let text, let rtf):
            return await importText(text, rtf: rtf, into: folder, sensitive: sensitive).map { [$0] } ?? []
        case .image(let data):
            return await importImage(data, into: folder, sensitive: sensitive).map { [$0] } ?? []
        case .nothing:
            return []
        }
    }

    // MARK: - Enrichment

    /// Extracts text, asks for a better title and tags, and renders a thumbnail.
    public func enrich(_ item: SummonItem, titleWasGiven: Bool) async {
        let id = item.id
        let kind = item.kind
        let sensitive = item.isEffectivelySensitive
        let key = store.vault.currentKey

        // 1. Get readable text out of the content.
        var extracted = ""
        if kind.isBlobBacked, let blob = item.storedBlob {
            if let url = try? store.files.materialize(blob, itemID: id, key: key) {
                extracted = await TextExtractor.extract(from: url, kind: kind)
                await makeThumbnail(for: id, from: url, sensitive: sensitive)
            }
        }

        guard let live = store.item(id: id) else { return }

        if !extracted.isEmpty {
            if sensitive, let key = store.vault.currentKey {
                live.sealedExtractedText = try? key.seal(extracted, itemID: id)
                live.extractedText = nil
            } else {
                live.extractedText = extracted
            }
        }

        // 2. Ask for a better title, tags and summary.
        let basisText: String
        if kind.isTextual {
            basisText = store.resolveBodyText(live, key: store.vault.currentKey) ?? ""
        } else {
            basisText = extracted
        }

        let suggestion = await intelligence.suggest(
            forText: basisText,
            kind: kind,
            filename: live.blobOriginalName.isEmpty ? nil : live.blobOriginalName,
            isSensitive: sensitive
        )

        guard let stillThere = store.item(id: id) else { return }
        if !titleWasGiven, !suggestion.title.isEmpty, suggestion.cameFromModel {
            stillThere.title = suggestion.title
        }
        if (stillThere.tags ?? []).isEmpty, !suggestion.tags.isEmpty {
            stillThere.tags = suggestion.tags.map { store.resolveTag(named: $0) }
        }
        if stillThere.summary == nil, stillThere.sealedSummary == nil {
            // Through the store, not straight onto the property: for a sensitive item
            // the heuristic summary is its own first sentence, so it has to be sealed.
            store.applySummary(stillThere, suggestion.summary)
        }
        stillThere.updatedAt = Date()

        store.save()
        store.refresh()
    }

    private func makeThumbnail(for id: UUID, from url: URL, sensitive: Bool) async {
        // Sensitive items get no plaintext thumbnail on disk — a preview of a passport
        // sitting unencrypted in a cache folder would defeat the point.
        guard !sensitive else { return }
        guard let png = await TextExtractor.thumbnail(for: url) else { return }
        try? png.write(to: store.files.thumbnailURL(itemID: id), options: .atomic)
    }

    /// Re-runs enrichment on demand, from the item's detail view.
    public func reEnrich(_ item: SummonItem) async {
        await enrich(item, titleWasGiven: true)
    }
}
