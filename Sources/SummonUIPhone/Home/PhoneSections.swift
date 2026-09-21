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

    typealias Section = LibrarySections.Section

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
    ///
    /// The split itself lives in `LibrarySections`, where it can be tested — the same
    /// rule a widget and a Shortcuts suggestion ask for.
    var sections: [Section] {
        if isSearching {
            return [Section(id: "results", title: "Results", items: filtered)]
        }
        return LibrarySections.split(filtered)
    }

    var isEmpty: Bool { sections.isEmpty }

    /// Whether rows can be dragged into a hand-made order right now.
    ///
    /// The same rule the Mac keeps: a folder is the only view with an order of its own
    /// to write to, and only while nothing is typed — under a search the list is in
    /// rank order, so a row dropped into place would spring straight back.
    var canReorder: Bool {
        if case .folder = model.sidebarSelection { return !isSearching }
        return false
    }

    /// Applies a drag within the current folder.
    ///
    /// SwiftUI hands over "these rows moved to there"; the store thinks in terms of one
    /// item placed beside another, which is what survives two devices editing the same
    /// folder. So the move is resolved to a neighbour before it is written.
    func move(_ items: [ItemSnapshot], from offsets: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: offsets, toOffset: destination)
        guard let movedID = offsets.first.map({ items[$0].id }),
              let newIndex = reordered.firstIndex(where: { $0.id == movedID }),
              let moved = model.store.item(id: movedID)
        else { return }

        if newIndex > 0, let previous = model.store.item(id: reordered[newIndex - 1].id) {
            model.store.reorderItem(moved, relativeTo: previous, placeAfter: true)
        } else if newIndex + 1 < reordered.count,
                  let next = model.store.item(id: reordered[newIndex + 1].id) {
            model.store.reorderItem(moved, relativeTo: next, placeAfter: false)
        }
        model.store.refresh()
        model.runSearch()
        Theme.Haptics.selection()
    }
}
#endif
