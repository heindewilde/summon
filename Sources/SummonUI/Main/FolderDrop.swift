/// Drag and drop, which is macOS-only until the companion decides its own story.
///
/// AppKit and UIKit both do drag and drop, but not the same way: iOS reaches for
/// `.dropDestination` and `Transferable` rather than `DropDelegate` and an
/// `NSItemProvider` unpacked by hand. Porting this is designing that, and it belongs
/// with the iOS UI work rather than with a pass over imports. Guarded rather than
/// moved to SummonUIMac for the same reason — these views are ones iPadOS will want.
#if canImport(AppKit)
import AppKit
import SummonKit
import SwiftUI
import UniformTypeIdentifiers

/// What is being dragged, as far as a drop target needs to care.
///
/// Decided from the types on the pasteboard, which is synchronous — the payload
/// itself can only be read asynchronously, and by then the indicator has to already
/// be on screen showing the right thing.
public enum DragCargo: Equatable, Sendable {
    /// A folder from our own sidebar. The only cargo that can be *reordered*, since
    /// it is the only one with a position among siblings.
    case folder
    /// A row from our own item list.
    case item
    /// Files, text, or anything else from outside. Always filed *into* a folder.
    case foreign

    init(_ info: DropInfo) {
        if info.hasItemsConforming(to: [SummonDragType.folder]) { self = .folder }
        else if info.hasItemsConforming(to: [SummonDragType.item]) { self = .item }
        else { self = .foreign }
    }

    /// Whether this cargo can be dropped beside a folder rather than inside it.
    var canReorder: Bool { self == .folder }
}

/// Every type a folder row is willing to receive.
public let FolderDropTypes: [UTType] = [SummonDragType.item, SummonDragType.folder,
                                        .fileURL, .text]

/// Drop handling for a folder row: reparent, reorder, file an item, and import from
/// outside, from one delegate.
///
/// A `DropDelegate` rather than `.onDrop`, because reordering needs to know *where*
/// in the row the pointer is — the top and bottom edges mean "put it beside this
/// one", the middle means "put it inside".
public struct FolderDropDelegate: DropDelegate {
    let folder: SummonFolder
    let model: AppModel

    /// Passed in rather than assumed: the delegate turns a pointer position into an
    /// intent, so it has to know how tall the row actually is.
    let rowHeight: CGFloat

    public init(folder: SummonFolder, model: AppModel, rowHeight: CGFloat) {
        self.folder = folder
        self.model = model
        self.rowHeight = rowHeight
    }

    private func mark(_ zone: FolderDropZone?) {
        model.setFolderDropTarget(zone.map { FolderDropTarget(folderID: folder.id, zone: $0) })
    }

    private func zone(for location: CGPoint, cargo: DragCargo,
                      current: FolderDropZone?) -> FolderDropZone {
        DropZoneResolver.zone(y: location.y, height: rowHeight,
                              canReorder: cargo.canReorder, current: current)
    }

    private func currentZone() -> FolderDropZone? {
        model.folderDropTarget?.folderID == folder.id ? model.folderDropTarget?.zone : nil
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: FolderDropTypes)
    }

    public func dropEntered(info: DropInfo) {
        mark(zone(for: info.location, cargo: DragCargo(info), current: currentZone()))
    }

    public func dropExited(info: DropInfo) {
        // Only clear if this row is still the one being marked: another row may have
        // taken over as the pointer moved on.
        if model.folderDropTarget?.folderID == folder.id { mark(nil) }
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        mark(zone(for: info.location, cargo: DragCargo(info), current: currentZone()))
        return DropProposal(operation: .move)
    }

    public func performDrop(info: DropInfo) -> Bool {
        let cargo = DragCargo(info)
        model.dropTrace?("performDrop cargo: \(cargo)")
        let target = currentZone() ?? .into
        model.setFolderDropTarget(nil)

        switch cargo {
        case .folder:
            let identity = SummonDrag.idFromDragPasteboard(SummonDragType.folder)
            let providers = info.itemProviders(for: [SummonDragType.folder])
            Task { @MainActor in
                guard let dragged = await SummonDrag.resolve(identity, type: SummonDragType.folder,
                                                            providers: providers),
                      let moving = model.store.folder(id: dragged)
                else { return }
                switch target {
                case .into: model.store.moveFolder(moving, under: folder)
                case .before: model.store.reorderFolder(moving, relativeTo: folder, placeAfter: false)
                case .after: model.store.reorderFolder(moving, relativeTo: folder, placeAfter: true)
                }
                model.runSearch()
            }

        case .item:
            // Read before the async hop: the drag pasteboard is only guaranteed to
            // hold its contents for the duration of the drop.
            let identity = SummonDrag.idFromDragPasteboard(SummonDragType.item)
            let providers = info.itemProviders(for: [SummonDragType.item])
            Task { @MainActor in
                guard let dragged = await SummonDrag.resolve(identity, type: SummonDragType.item,
                                                            providers: providers)
                else {
                    model.dropTrace?("item drop: no identity on the drag")
                    return
                }
                model.fileItem(dragged, into: folder)
                model.dropTrace?("filed \(dragged) into \(folder.name)")
            }

        case .foreign:
            model.acceptForeignDrop(info, into: folder)
        }
        return true
    }
}

/// Reading our own identifiers back off a drag.
///
/// Main-actor bound because that is where every caller lives — a drop delegate and
/// the model — and hopping off it would only mean handing `NSItemProvider`s across
/// an isolation boundary for no gain.
@MainActor
public enum SummonDrag {

    /// The drag pasteboard, read directly.
    ///
    /// The route that actually works. SwiftUI hands `performDrop` an `NSItemProvider`
    /// with an empty `registeredTypeIdentifiers` for a custom type — it knows the
    /// drag conforms (that is how the cargo is recognised at all) but will not vend
    /// the representation back. The pasteboard underneath it has the bytes.
    public static func idFromDragPasteboard(_ type: UTType) -> UUID? {
        SummonDragType.read(type, from: NSPasteboard(name: .drag))
    }

    /// Asks the providers, for the cases the pasteboard cannot answer — a drag from
    /// another process, or a promise resolved late.
    public static func id(from providers: [NSItemProvider], type: UTType) async -> UUID? {
        for provider in providers {
            if let data = await data(from: provider, type: type),
               let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) {
                return id
            }
        }
        return nil
    }

    /// The identity already read off the pasteboard, or failing that, the providers.
    ///
    /// Two steps rather than one because they cannot happen in the same place: the
    /// pasteboard has to be read synchronously, inside `performDrop`, while the
    /// providers can only be read after an `await`.
    public static func resolve(_ identity: UUID?, type: UTType,
                               providers: [NSItemProvider]) async -> UUID? {
        if let identity { return identity }
        return await id(from: providers, type: type)
    }

    private static func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

@MainActor
extension FolderDropDelegate {
    /// File URLs out of a set of drag providers.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
            } else if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                urls.append(url)
            }
        }
        return urls
    }

    /// Plain text out of a set of drag providers.
    static func text(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier) as? String,
               !text.isEmpty {
                return text
            }
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier) as? Data,
               case let text = String(decoding: data, as: UTF8.self), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}

/// The drop target for the top level, so a nested folder — or a filed item — can be
/// dragged back out. Without it you could nest but never fully un-nest by dragging.
public struct RootFolderDropDelegate: DropDelegate {
    let model: AppModel
    @Binding var isTargeted: Bool

    public init(model: AppModel, isTargeted: Binding<Bool>) {
        self.model = model
        _isTargeted = isTargeted
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: SummonDragType.all)
    }

    public func dropEntered(info: DropInfo) {
        isTargeted = true
        // The row indicator and this one are the same signal; showing both at once
        // said the drop would land in two places.
        model.setFolderDropTarget(nil)
    }

    public func dropExited(info: DropInfo) { isTargeted = false }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        model.setFolderDropTarget(nil)
        return DropProposal(operation: .move)
    }

    public func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        model.setFolderDropTarget(nil)

        if info.hasItemsConforming(to: [SummonDragType.folder]) {
            let identity = SummonDrag.idFromDragPasteboard(SummonDragType.folder)
            let providers = info.itemProviders(for: [SummonDragType.folder])
            Task { @MainActor in
                guard let dragged = await SummonDrag.resolve(identity, type: SummonDragType.folder,
                                                            providers: providers),
                      let moving = model.store.folder(id: dragged)
                else { return }
                model.store.moveFolder(moving, under: nil)
                model.runSearch()
            }
            return true
        }

        let identity = SummonDrag.idFromDragPasteboard(SummonDragType.item)
        let providers = info.itemProviders(for: [SummonDragType.item])
        Task { @MainActor in
            guard let dragged = await SummonDrag.resolve(identity, type: SummonDragType.item,
                                                        providers: providers)
            else { return }
            model.fileItem(dragged, into: nil)
        }
        return true
    }
}
#endif
