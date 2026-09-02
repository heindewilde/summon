import AppKit
import SummonKit
import SwiftUI
import UniformTypeIdentifiers

/// Where a dragged folder would land relative to the row under the pointer.
public enum FolderDropZone: Equatable, Sendable {
    case before
    case into
    case after
}

/// Drop handling for a folder row: reparent, reorder, and file import, from one
/// delegate.
///
/// A `DropDelegate` rather than `.onDrop`, because reordering needs to know *where*
/// in the row the pointer is — the top and bottom quarters mean "put it beside this
/// one", the middle half means "put it inside".
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
        model.folderDropTarget = zone.map { FolderDropTarget(folderID: folder.id, zone: $0) }
    }

    private func zone(for location: CGPoint) -> FolderDropZone {
        let edge = rowHeight * 0.3
        if location.y < edge { return .before }
        if location.y > rowHeight - edge { return .after }
        return .into
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text]) || info.hasItemsConforming(to: [.fileURL])
    }

    public func dropEntered(info: DropInfo) { mark(zone(for: info.location)) }

    public func dropExited(info: DropInfo) {
        // Only clear if this row is still the one being marked: another row may have
        // taken over as the pointer moved on.
        if model.folderDropTarget?.folderID == folder.id { mark(nil) }
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        mark(zone(for: info.location))
        return DropProposal(operation: .move)
    }

    public func performDrop(info: DropInfo) -> Bool {
        let target = model.folderDropTarget?.folderID == folder.id
            ? (model.folderDropTarget?.zone ?? .into) : .into
        model.folderDropTarget = nil

        if info.hasItemsConforming(to: [.text]) {
            let providers = info.itemProviders(for: [.text])
            Task { @MainActor in
                guard let dragged = await FolderDropDelegate.folderID(from: providers),
                      let moving = model.store.allFolders().first(where: { $0.id == dragged })
                else { return }
                switch target {
                case .into: model.store.moveFolder(moving, under: folder)
                case .before: model.store.reorderFolder(moving, relativeTo: folder, placeAfter: false)
                case .after: model.store.reorderFolder(moving, relativeTo: folder, placeAfter: true)
                }
                model.runSearch()
            }
            return true
        }

        let providers = info.itemProviders(for: [.fileURL])
        Task { @MainActor in
            let urls = await FolderDropDelegate.urls(from: providers)
            guard !urls.isEmpty else { return }
            model.importDroppedFiles(urls, into: folder)
        }
        return true
    }

    static func folderID(from providers: [NSItemProvider]) async -> UUID? {
        for provider in providers {
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier) as? Data,
               let text = String(data: data, encoding: .utf8),
               let id = UUID(uuidString: text.replacingOccurrences(of: FolderDragPrefix, with: "")),
               text.hasPrefix(FolderDragPrefix) {
                return id
            }
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier) as? String,
               text.hasPrefix(FolderDragPrefix),
               let id = UUID(uuidString: String(text.dropFirst(FolderDragPrefix.count))) {
                return id
            }
        }
        return nil
    }
}

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
}

/// Marks a dragged string as a folder rather than arbitrary text someone dropped in
/// from another app.
public let FolderDragPrefix = "summon.folder:"

/// The drop target for the top level, so a nested folder can be dragged back out.
/// Without it you could nest but never fully un-nest by dragging.
public struct RootFolderDropDelegate: DropDelegate {
    let model: AppModel
    @Binding var isTargeted: Bool

    public init(model: AppModel, isTargeted: Binding<Bool>) {
        self.model = model
        _isTargeted = isTargeted
    }

    public func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }
    public func dropEntered(info: DropInfo) { isTargeted = true }
    public func dropExited(info: DropInfo) { isTargeted = false }

    public func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        model.folderDropTarget = nil
        let providers = info.itemProviders(for: [.text])
        Task { @MainActor in
            guard let dragged = await FolderDropDelegate.folderID(from: providers),
                  let moving = model.store.allFolders().first(where: { $0.id == dragged })
            else { return }
            model.store.moveFolder(moving, under: nil)
            model.runSearch()
        }
        return true
    }
}
