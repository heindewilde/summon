// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// What the home screen shows, and in what order.
///
/// The Mac answers this with its panel: pinned first, then recent, then the app you
/// were in. A phone has no app you were in, so the third section has nothing to say —
/// which is exactly what `SearchIndex` already assumes when the bundle id is nil.
///
/// Kept out of `AppModel` because these are phone-shaped questions. The ranking
/// underneath is the shared one; this only decides what to ask it for.
@MainActor
struct PhoneSections {
    let model: AppModel

    struct Section: Identifiable {
        let id: String
        let title: String
        let items: [ItemSnapshot]
    }

    /// The filter written into the search field, if any: a folder, a tag, or a kind.
    /// Everything below is filtered by it, so the chips and the query stay one thing.
    private var filtered: [ItemSnapshot] {
        model.itemsForSidebar()
    }

    var isSearching: Bool {
        !model.mainSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// While searching, one ranked list. The sections are for the resting state:
    /// splitting ranked results into groups hides the ranking, which is the thing
    /// doing the work.
    var sections: [Section] {
        if isSearching {
            return [Section(id: "results", title: "Results", items: filtered)]
        }

        let pinned = filtered.filter(\.isPinned)
        let recent = filtered
            .filter { $0.lastUsedAt != nil && !$0.isPinned }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(8)
        let pinnedOrRecent = Set(pinned.map(\.id)).union(recent.map(\.id))
        let rest = filtered
            .filter { !pinnedOrRecent.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }

        return [
            Section(id: "pinned", title: "Pinned", items: pinned),
            Section(id: "recent", title: "Recent", items: Array(recent)),
            Section(id: "everything", title: pinnedOrRecent.isEmpty ? "Everything" : "More",
                    items: rest),
        ].filter { !$0.items.isEmpty }
    }

    var isEmpty: Bool { sections.isEmpty }
}
#endif
