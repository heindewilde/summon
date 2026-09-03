import Foundation
import SummonKit
import SwiftUI

/// One folder row, as a value.
///
/// The sidebar used to walk the SwiftData tree inside its `body`: a fetch of the
/// folder table, a recursive sort, and a recursive item count for every row — all of
/// it repeated on every single body evaluation. That was tolerable until dragging,
/// which re-evaluates continuously, at which point the tree was being rebuilt dozens
/// of times a second. Rows are plain values now, computed once per change.
public struct SidebarFolderRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let symbolName: String
    public let colorName: String
    public let depth: Int
    public let hasChildren: Bool
    public let isCollapsed: Bool
    public let isSensitive: Bool

    /// Items filed in this folder itself — the same set selecting it will show, so
    /// the count and the list can never disagree.
    public let itemCount: Int
}

/// The counts beside the fixed Library rows, computed together in one pass.
public struct SidebarCounts: Equatable, Sendable {
    public var all = 0
    public var recents = 0
    public var pinned = 0
    public var sensitive = 0
    public var kinds: [ItemKind: Int] = [:]
}

extension AppModel {

    /// The folder tree, flattened to rows.
    ///
    /// Flattened so the tree is one list: a nested `ForEach` inside a lazy stack
    /// cannot give a stable drop target, and depth is just an indent.
    public var sidebarFolderRows: [SidebarFolderRow] {
        let revision = store.revision
        let collapsed = collapsedFolders
        if let cache = folderRowCache, cache.revision == revision, cache.collapsed == collapsed {
            return cache.rows
        }

        var rows: [SidebarFolderRow] = []
        func walk(_ folders: [SummonFolder], _ depth: Int) {
            for folder in folders {
                let children = folder.sortedChildren
                rows.append(SidebarFolderRow(
                    id: folder.id,
                    name: folder.name,
                    symbolName: folder.symbolName,
                    colorName: folder.colorName,
                    depth: depth,
                    hasChildren: !children.isEmpty,
                    isCollapsed: collapsed.contains(folder.id),
                    isSensitive: folder.isEffectivelySensitive,
                    itemCount: (folder.items ?? []).count
                ))
                if !collapsed.contains(folder.id) { walk(children, depth + 1) }
            }
        }
        walk(store.rootFolders(), 0)

        folderRowCache = (revision, collapsed, rows)
        return rows
    }

    public var sidebarCounts: SidebarCounts {
        let revision = store.revision
        if let cache = sidebarCountCache, cache.revision == revision { return cache.counts }

        var counts = SidebarCounts()
        counts.all = store.snapshots.count
        for snapshot in store.snapshots {
            if snapshot.lastUsedAt != nil { counts.recents += 1 }
            if snapshot.isPinned { counts.pinned += 1 }
            if snapshot.isSensitive { counts.sensitive += 1 }
            // Every textual kind counts towards the one "Text" row the sidebar shows.
            counts.kinds[snapshot.kind.isTextual ? .text : snapshot.kind, default: 0] += 1
        }

        sidebarCountCache = (revision, counts)
        return counts
    }

    public func toggleFolderCollapsed(_ id: UUID) {
        if collapsedFolders.contains(id) { collapsedFolders.remove(id) }
        else { collapsedFolders.insert(id) }
    }
}
