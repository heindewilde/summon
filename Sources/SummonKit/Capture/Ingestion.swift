import Foundation

/// Saving something into the library, with nothing else attached.
///
/// An extension gets a few seconds and a few dozen megabytes. `AppModel` is the whole
/// app — search index, clipboard, intelligence, settings, vault timers — and loading
/// it to write one item is how share extensions come to feel slow and get killed.
/// This is the other end: a store, an importer, and the three things a share sheet can
/// hand over.
///
/// It deliberately does *not* migrate. Migrations rewrite every payload in the
/// library; an extension that started one and was killed halfway would leave the app
/// to find the mess. If the store is older than this build expects, it says so and
/// declines — the container app will migrate the next time it is opened.
@MainActor
public final class Ingestion {
    public enum Failure: LocalizedError {
        case libraryUnavailable
        case needsTheApp
        case nothingUsable

        public var errorDescription: String? {
            switch self {
            case .libraryUnavailable: "Summon couldn’t open your library."
            case .needsTheApp: "Open Summon once to finish updating your library, then try again."
            case .nothingUsable: "There was nothing here Summon could save."
            }
        }
    }

    private let store: LibraryStore
    private let importer: Importer

    public convenience init() throws {
        try self.init(paths: LibraryPaths.standard())
    }

    /// Takes its paths so a test can point it at a throwaway library. An extension
    /// always uses `standard()`, which is the App Group container.
    public init(paths: LibraryPaths) throws {
        let vault = Vault(paths: paths, syncsMasterKey: false)
        // Never mirrors: an extension that opened a CloudKit-backed container would
        // start a sync it has no time to finish. The container app exports what lands
        // here the next time it runs.
        guard let store = try? LibraryStore(paths: paths, vault: vault, syncs: false,
                                            migrates: false) else {
            throw Failure.libraryUnavailable
        }
        guard store.isMigrated else { throw Failure.needsTheApp }
        self.store = store
        // No language model: suggestions are the app's job, where there is time for
        // them, and asking one here would spend the extension's seconds on a title it
        // could guess instantly. Text still gets a heuristic title.
        let intelligence = Intelligence()
        intelligence.isEnabled = false
        self.importer = Importer(store: store, intelligence: intelligence)
    }

    /// Everything a share sheet can hand over, in the order it is preferred.
    public enum Payload {
        case files([URL])
        case image(Data)
        case text(String, rtf: Data?)
    }

    @discardableResult
    public func save(_ payload: Payload) async throws -> String {
        let item: SummonItem?
        switch payload {
        case .files(let urls):
            item = await importer.importFiles(urls).first
        case .image(let data):
            item = await importer.importImage(data)
        case .text(let text, let rtf):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Failure.nothingUsable }
            item = await importer.importText(text, rtf: rtf)
        }
        guard let item else { throw Failure.nothingUsable }
        store.save()
        return item.title
    }
}
