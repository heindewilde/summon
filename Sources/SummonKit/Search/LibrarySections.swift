import Foundation

/// How a library divides into what you reach for and everything else.
///
/// The Mac's panel answers this with `SearchIndex`, which also knows about the app you
/// were in a moment ago. A phone has no such app, so the split is simpler — pinned,
/// recently used, the rest — and it is the same question a widget and a Shortcuts
/// suggestion ask.
///
/// Here rather than in the phone's view layer because a rule about ordering is worth a
/// test, and a view built around `AppModel` cannot have one: the iOS view target does
/// not compile for the machine the tests run on.
public enum LibrarySections {
    public struct Section: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let items: [ItemSnapshot]

        public init(id: String, title: String, items: [ItemSnapshot]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    /// How many recently-used items are worth showing before the list stops being a
    /// shortcut and starts being the library again.
    public static let recentLimit = 8

    /// Splits `items`, which are expected to be already filtered to the current view.
    ///
    /// Empty sections are dropped rather than shown empty, and an item appears once:
    /// a pinned item that was also used this morning belongs under Pinned, because
    /// that is the promise pinning makes.
    public static func split(_ items: [ItemSnapshot], recentLimit: Int = recentLimit) -> [Section] {
        let pinned = items.filter(\.isPinned)
        let recent = items
            .filter { $0.lastUsedAt != nil && !$0.isPinned }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(recentLimit)

        let spokenFor = Set(pinned.map(\.id)).union(recent.map(\.id))
        let rest = items
            .filter { !spokenFor.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }

        return [
            Section(id: "pinned", title: "Pinned", items: pinned),
            Section(id: "recent", title: "Recent", items: Array(recent)),
            // "Everything" when it is the only section, "More" when it is the tail of
            // a list: the same rows mean different things depending on what is above.
            Section(id: "everything", title: spokenFor.isEmpty ? "Everything" : "More", items: rest),
        ].filter { !$0.items.isEmpty }
    }
}
