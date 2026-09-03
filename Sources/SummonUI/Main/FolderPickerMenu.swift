import SummonKit
import SwiftUI

/// "Move to Folder ▸" — the folder tree as a nested submenu.
///
/// The tree rather than a flat list of paths, because a flat list turns "Acme" into
/// "Clients › 2026 › Acme" and stops being scannable at about a dozen folders. Each
/// branch names itself first, so a folder that has children is still a destination
/// in its own right — hovering "Clients ▸" and clicking "Clients" files it there,
/// while its children stay one step further along.
struct FolderPickerMenu: View {
    @Bindable var model: AppModel
    let item: ItemSnapshot

    var body: some View {
        Menu {
            Button("No Folder", systemImage: "tray") {
                model.fileItem(item.id, intoFolderID: nil)
            }
            .disabled(item.folderID == nil)

            let roots = model.folderTreeForMenu
            if !roots.isEmpty {
                Divider()
                ForEach(roots) { node in
                    FolderPickerMenu.branch(node, current: item.folderID) {
                        model.fileItem(item.id, intoFolderID: $0)
                    }
                }
            }

            Divider()
            Button("New Folder…", systemImage: "folder.badge.plus") {
                model.fileItemIntoNewFolder(item.id)
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
    }

    /// Built as `AnyView` on purpose: a `View` struct whose body contains itself is
    /// a circular opaque type and will not compile, and a menu is small enough that
    /// the erasure costs nothing.
    @MainActor
    static func branch(_ node: FolderMenuNode, current: UUID?,
                       move: @escaping (UUID) -> Void) -> AnyView {
        let label = Label(node.name, systemImage: node.symbolName)
        guard !node.children.isEmpty else {
            return AnyView(
                Button { move(node.id) } label: { label }
                    .disabled(node.id == current)
            )
        }
        return AnyView(
            Menu {
                Button { move(node.id) } label: { label }
                    .disabled(node.id == current)
                Divider()
                ForEach(node.children) { child in
                    branch(child, current: current, move: move)
                }
            } label: {
                label
            }
        )
    }
}

/// The folder tree as values, for the menu to walk without touching SwiftData.
public struct FolderMenuNode: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let symbolName: String
    public let children: [FolderMenuNode]
}

extension AppModel {
    /// The whole tree, regardless of what the sidebar has collapsed — a submenu that
    /// hid destinations because a row happened to be folded shut would be a trap.
    public var folderTreeForMenu: [FolderMenuNode] {
        func build(_ folders: [SummonFolder], depth: Int) -> [FolderMenuNode] {
            // Bounded in case a bad move ever produced a cycle; the store refuses to
            // create one, and a menu is not the place to discover otherwise.
            guard depth < 12 else { return [] }
            return folders.map {
                FolderMenuNode(id: $0.id, name: $0.name, symbolName: $0.symbolName,
                               children: build($0.sortedChildren, depth: depth + 1))
            }
        }
        return build(store.rootFolders(), depth: 0)
    }

    /// "New Folder…" from the item's context menu: makes the folder, files the item
    /// in it, and leaves the name selected for typing — the same flow as the sidebar
    /// button, with the item already inside.
    public func fileItemIntoNewFolder(_ id: UUID) {
        let folder = store.createFolder(name: "New Folder", parent: nil)
        fileItem(id, into: folder)
        sidebarSelection = .folder(folder.id)
        renamingFolderID = folder.id
    }
}
