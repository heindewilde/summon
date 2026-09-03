import AppKit
import SummonKit
import SwiftUI
import UniformTypeIdentifiers

/// Where a dragged item would land relative to the row under the pointer.
public struct ItemDropTarget: Equatable, Sendable {
    public let itemID: UUID
    public let placeAfter: Bool
    public init(itemID: UUID, placeAfter: Bool) {
        self.itemID = itemID
        self.placeAfter = placeAfter
    }
}

/// Drag-to-reorder for the item list.
///
/// Only inside a folder, and only when nothing is typed in the search field. Every
/// other view has an ordering rule of its own — recency, use count, search rank —
/// and a hand-made order cannot survive being shown under one of those: you would
/// drop a row into place and watch it jump straight back.
@MainActor
public struct ItemReorderDropDelegate: DropDelegate {
    let item: ItemSnapshot
    let model: AppModel
    let rowHeight: CGFloat

    public init(item: ItemSnapshot, model: AppModel, rowHeight: CGFloat) {
        self.item = item
        self.model = model
        self.rowHeight = rowHeight
    }

    /// Above the midpoint means before, below means after — with the same hysteresis
    /// the folder rows use, so the line does not flicker across the boundary.
    private func placeAfter(_ location: CGPoint) -> Bool {
        let current = model.itemDropTarget?.itemID == item.id ? model.itemDropTarget?.placeAfter : nil
        return DropZoneResolver.placeAfter(y: location.y, height: rowHeight, current: current)
    }

    private func mark(_ location: CGPoint?) {
        model.setItemDropTarget(location.map {
            ItemDropTarget(itemID: item.id, placeAfter: placeAfter($0))
        })
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [SummonDragType.item])
    }

    public func dropEntered(info: DropInfo) { mark(info.location) }

    public func dropExited(info: DropInfo) {
        if model.itemDropTarget?.itemID == item.id { mark(nil) }
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        mark(info.location)
        return DropProposal(operation: .move)
    }

    public func performDrop(info: DropInfo) -> Bool {
        let after = model.itemDropTarget?.itemID == item.id
            ? (model.itemDropTarget?.placeAfter ?? false) : false
        model.setItemDropTarget(nil)

        // Read before the async hop: the drag pasteboard is only guaranteed to hold
        // its contents for the duration of the drop.
        let identity = SummonDrag.idFromDragPasteboard(SummonDragType.item)
        let providers = info.itemProviders(for: [SummonDragType.item])
        Task { @MainActor in
            guard let dragged = await SummonDrag.resolve(identity, type: SummonDragType.item,
                                                        providers: providers)
            else { return }
            model.reorderItem(dragged, relativeTo: item.id, placeAfter: after)
        }
        return true
    }
}

/// The item list's background.
///
/// Its job is to accept things from *outside* — a file, a paragraph — into whatever
/// folder is showing. It has to actively refuse Summon's own drags: an item dragged
/// over the empty space below the rows still carries its contents, so a plain
/// content-based handler cheerfully re-imported it as a duplicate of itself. That is
/// the same mistake the sidebar used to make, one column over.
@MainActor
public struct LibraryDropDelegate: DropDelegate {
    let model: AppModel
    let folder: () -> SummonFolder?

    public init(model: AppModel, folder: @escaping () -> SummonFolder?) {
        self.model = model
        self.folder = folder
    }

    public func validateDrop(info: DropInfo) -> Bool {
        DragCargo(info) == .foreign
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: DragCargo(info) == .foreign ? .copy : .forbidden)
    }

    public func performDrop(info: DropInfo) -> Bool {
        guard DragCargo(info) == .foreign else { return false }
        model.acceptForeignDrop(info, into: folder())
        return true
    }
}
