import AppKit
import SummonKit
import SwiftUI
import UniformTypeIdentifiers

/// Where a dragged folder would land relative to the row under the pointer.
public enum FolderDropZone: Equatable {
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
    @Binding var zone: FolderDropZone?

    /// The height of a sidebar row, used to turn a pointer position into an intent.
    private static let rowHeight: CGFloat = 24

    public init(folder: SummonFolder, model: AppModel, zone: Binding<FolderDropZone?>) {
        self.folder = folder
        self.model = model
        _zone = zone
    }

    private func zone(for location: CGPoint) -> FolderDropZone {
        let edge = Self.rowHeight * 0.28
        if location.y < edge { return .before }
        if location.y > Self.rowHeight - edge { return .after }
        return .into
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text]) || info.hasItemsConforming(to: [.fileURL])
    }

    public func dropEntered(info: DropInfo) { zone = zone(for: info.location) }
    public func dropExited(info: DropInfo) { zone = nil }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        zone = zone(for: info.location)
        return DropProposal(operation: .move)
    }

    public func performDrop(info: DropInfo) -> Bool {
        let target = zone ?? .into
        zone = nil

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
            let urls = await FolderRow.urls(from: providers)
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
