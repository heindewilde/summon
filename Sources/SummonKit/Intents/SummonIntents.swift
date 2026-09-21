#if canImport(AppIntents)
import AppIntents
import Foundation

/// Summon, from outside Summon: Shortcuts, Siri, the Control Centre, a widget.
///
/// Every intent here goes through `Ingestion` or a read of the snapshots — never
/// `AppModel`. An intent runs in whatever process the system chooses, often with the
/// app not running at all, and that process gets the same seconds an extension does.

/// One item, as Shortcuts sees it.
public struct SummonItemEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Item")
    public static let defaultQuery = SummonItemQuery()

    public var id: UUID
    public var title: String
    public var kind: String
    public var isLocked: Bool

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(kind)")
    }

    public init(id: UUID, title: String, kind: String, isLocked: Bool) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isLocked = isLocked
    }

    public init(_ snapshot: ItemSnapshot) {
        self.init(id: snapshot.id, title: snapshot.title,
                  kind: snapshot.kind.displayName, isLocked: snapshot.isLocked)
    }
}

/// How Shortcuts finds items to offer.
///
/// Locked items are listed but never resolved to their contents: a shortcut that could
/// read a sealed passport scan without the vault being open would be a hole straight
/// through the thing the vault is for.
public struct SummonItemQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [SummonItemEntity] {
        try await snapshots().filter { identifiers.contains($0.id) }.map(SummonItemEntity.init)
    }

    public func entities(matching string: String) async throws -> [SummonItemEntity] {
        let query = string.lowercased()
        return try await snapshots()
            .filter { $0.title.lowercased().contains(query) }
            .prefix(25)
            .map(SummonItemEntity.init)
    }

    public func suggestedEntities() async throws -> [SummonItemEntity] {
        try await snapshots()
            .filter(\.isPinned)
            .prefix(10)
            .map(SummonItemEntity.init)
    }

    @MainActor
    private func snapshots() throws -> [ItemSnapshot] {
        try IntentLibrary.shared().snapshots
    }
}

/// Puts an item on the clipboard. The phone's whole summon moment, from anywhere.
public struct SummonItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Summon Item"
    public static let description = IntentDescription(
        "Copies one of your Summon items to the clipboard.")
    /// The point is the clipboard, and a shortcut that silently opened the app instead
    /// would be a worse version of tapping the icon.
    public static let openAppWhenRun = false

    @Parameter(title: "Item")
    public var item: SummonItemEntity

    public init() {}
    public init(item: SummonItemEntity) { self.item = item }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let library = try IntentLibrary.shared()
        guard let payload = library.payload(for: item.id) else {
            // Either it is sealed, or it wants fill-in values. Both are questions, and
            // an intent has nowhere to ask them.
            return .result(dialog: "Open Summon to use “\(item.title)”.")
        }
        Pasteboard.write(payload)
        return .result(dialog: "Copied “\(item.title)”.")
    }
}

/// Saves text into the library — the other direction, for a shortcut that ends in
/// "…and keep this".
public struct SaveToSummonIntent: AppIntent {
    public static let title: LocalizedStringResource = "Save to Summon"
    public static let description = IntentDescription("Saves text into your Summon library.")
    public static let openAppWhenRun = false

    @Parameter(title: "Text")
    public var text: String

    public init() {}
    public init(text: String) { self.text = text }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = try await Ingestion().save(.text(text, rtf: nil))
        return .result(dialog: "Saved “\(title)”.")
    }
}

public struct SummonShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SummonItemIntent(),
                    phrases: ["Summon an item with \(.applicationName)",
                              "Summon with \(.applicationName)"],
                    shortTitle: "Summon Item",
                    systemImageName: "sparkles")
        AppShortcut(intent: SaveToSummonIntent(),
                    phrases: ["Save this to \(.applicationName)"],
                    shortTitle: "Save to Summon",
                    systemImageName: "tray.and.arrow.down")
    }
}
#endif
