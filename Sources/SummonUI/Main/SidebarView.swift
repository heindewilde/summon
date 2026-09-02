import AppKit
import SummonKit
import SwiftUI

/// The sidebar.
///
/// Drawn as a scroll view rather than a `List`, for the same reason the item list
/// is: `.onDrag` on a List row swallows the click that selects it, and a List gives
/// a drop handler no dependable position, so "between these two folders" was
/// guesswork. Owning the rows means selection, dragging and the drop indicator all
/// work at once, and the selected row can be a quiet fill instead of the system's
/// accent blue.
public struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renameText = ""
    @State private var collapsed: Set<UUID> = []
    @State private var rootTargeted = false

    public init(model: AppModel) { self.model = model }

    private static let rowHeight: CGFloat = 26

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header("Library")
                row(.all, "All Items", "square.grid.2x2", count: model.store.snapshots.count)
                row(.recents, "Recents", "clock",
                    count: model.store.snapshots.count { $0.lastUsedAt != nil })
                row(.pinned, "Pinned", "pin", count: model.store.snapshots.count(where: \.isPinned))
                if model.vault.isConfigured {
                    row(.locked, "Sensitive", "lock",
                        count: model.store.snapshots.count(where: \.isSensitive))
                }
                row(.clipboard, "Clipboard", "doc.on.clipboard",
                    count: model.clipboard.entries.count)

                header("Folders")
                ForEach(flattenedFolders, id: \.folder.id) { entry in
                    FolderRow(model: model,
                              folder: entry.folder,
                              depth: entry.depth,
                              hasChildren: !entry.folder.sortedChildren.isEmpty,
                              isCollapsed: collapsed.contains(entry.folder.id),
                              rowHeight: Self.rowHeight,
                              renameText: $renameText,
                              onToggle: { toggle(entry.folder.id) })
                }
                newFolderButton

                let tags = model.store.tagsInUse()
                if !tags.isEmpty {
                    header("Tags")
                    ForEach(tags, id: \.id) { tag in
                        // The name only: the icon column already carries the "#".
                        row(.tag(tag.name), tag.name, "number",
                            count: (tag.items ?? []).count, tint: Theme.tertiaryText)
                    }
                }

                header("Types")
                ForEach(ItemKind.allCases.filter { $0 != .richText }, id: \.self) { kind in
                    let count = model.store.snapshots.count {
                        kind == .text ? $0.kind.isTextual : $0.kind == kind
                    }
                    if count > 0 {
                        row(.kind(kind), kind.pluralName, kind.symbolName,
                            count: count, tint: Theme.color(for: kind))
                    }
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.m)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Folder tree

    private struct FolderEntry { let folder: SummonFolder; let depth: Int }

    /// Flattened so the tree is one list of rows: a nested `ForEach` inside a lazy
    /// stack cannot give a stable drop target, and depth is just an indent.
    private var flattenedFolders: [FolderEntry] {
        var out: [FolderEntry] = []
        func walk(_ folders: [SummonFolder], _ depth: Int) {
            for folder in folders {
                out.append(FolderEntry(folder: folder, depth: depth))
                if !collapsed.contains(folder.id) { walk(folder.sortedChildren, depth + 1) }
            }
        }
        walk(model.store.rootFolders(), 0)
        return out
    }

    private func toggle(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private var newFolderButton: some View {
        Button {
            model.beginNewFolder()
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text("New Folder")
                Spacer(minLength: 0)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, Theme.Space.xs)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Also the top-level drop target: without somewhere to drop *outside* every
        // folder, a nested folder could be nested deeper but never dragged back out.
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(rootTargeted ? Theme.selection : .clear)
        }
        .onDrop(of: [.text], delegate: RootFolderDropDelegate(model: model, isTargeted: $rootTargeted))
    }

    // MARK: - Plain rows

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typography.section)
            .foregroundStyle(Theme.tertiaryText)
            .tracking(0.5)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xxs)
    }

    private func row(_ selection: SidebarSelection, _ title: String, _ symbol: String,
                     count: Int, tint: Color = Theme.secondaryText) -> some View {
        let isSelected = model.sidebarSelection == selection
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.xs)
            if count > 0 {
                Text("\(count)")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Self.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isSelected ? Theme.selection : .clear)
        }
        .contentShape(.rect)
        .onTapGesture { model.sidebarSelection = selection }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count > 0 ? "\(title), \(count) items" : title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// One folder in the tree.
struct FolderRow: View {
    @Bindable var model: AppModel
    let folder: SummonFolder
    let depth: Int
    let hasChildren: Bool
    let isCollapsed: Bool
    let rowHeight: CGFloat
    @Binding var renameText: String
    let onToggle: () -> Void

    @State private var dropZone: FolderDropZone?
    @State private var pickingIcon = false
    @FocusState private var nameFocused: Bool

    private var isSelected: Bool { model.sidebarSelection == .folder(folder.id) }
    private var isRenaming: Bool { model.renamingFolderID == folder.id }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 12, height: 12)
                    .contentShape(.rect)
                    .opacity(hasChildren ? 1 : 0)
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)
            .accessibilityHidden(!hasChildren)
            .accessibilityLabel(isCollapsed ? "Expand" : "Collapse")

            Button { pickingIcon = true } label: {
                Image(systemName: folder.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.folderColor(folder.colorName))
                    .frame(width: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Change icon")
            .accessibilityLabel("Change the icon for \(folder.name)")
            .popover(isPresented: $pickingIcon, arrowEdge: .trailing) {
                FolderIconPicker(model: model, folder: folder, isPresented: $pickingIcon)
            }

            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { model.renamingFolderID = nil }
                    .onAppear { renameText = folder.name; nameFocused = true }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
            } else {
                Text(folder.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.xs)

            if folder.isEffectivelySensitive {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .accessibilityHidden(true)
            }
            let count = folder.allItems().count
            if count > 0 {
                Text("\(count)")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
            }
        }
        .padding(.leading, CGFloat(depth) * 14 + Theme.Space.xs)
        .padding(.trailing, Theme.Space.xs)
        .frame(height: rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                // A fill means the drop goes *inside* this folder.
                .fill(dropZone == .into ? Theme.selection
                      : (isSelected ? Theme.selection : .clear))
        }
        // A line means the drop goes *beside* it.
        .overlay(alignment: .top) { if dropZone == .before { dropLine } }
        .overlay(alignment: .bottom) { if dropZone == .after { dropLine } }
        .contentShape(.rect)
        .onTapGesture { model.sidebarSelection = .folder(folder.id) }
        .onDrag {
            model.sidebarSelection = .folder(folder.id)
            // Prefixed so a folder drag is distinguishable from text dropped in from
            // another app.
            return NSItemProvider(object: (FolderDragPrefix + folder.id.uuidString) as NSString)
        }
        .onDrop(of: [.text, .fileURL],
                delegate: FolderDropDelegate(folder: folder, model: model,
                                             rowHeight: rowHeight, zone: $dropZone))
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count(for: folder))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func count(for folder: SummonFolder) -> String {
        let n = folder.allItems().count
        return n > 0 ? "\(folder.name), \(n) items" : folder.name
    }

    private func commitRename() {
        guard isRenaming else { return }
        model.store.renameFolder(folder, to: renameText)
        model.renamingFolderID = nil
    }

    @ViewBuilder
    private var menu: some View {
        Button("Rename") {
            renameText = folder.name
            model.renamingFolderID = folder.id
        }
        Button("Change Icon…") { pickingIcon = true }
        Button("New Folder Inside") {
            let child = model.store.createFolder(name: "New Folder", parent: folder)
            model.sidebarSelection = .folder(child.id)
            model.renamingFolderID = child.id
        }
        Button("Add Files…") { model.presentImportPanel(into: folder) }
        Divider()
        Button(folder.isSensitive ? "Remove Sensitivity" : "Mark as Sensitive") {
            model.setFolderSensitive(folder, !folder.isSensitive)
        }
        Divider()
        Button("Delete Folder", role: .destructive) {
            model.store.deleteFolder(folder)
            model.runSearch()
        }
    }
}

/// A folder row's insertion indicator.
private var dropLine: some View {
    Rectangle()
        .fill(Theme.primaryText)
        .frame(height: 2)
        .padding(.horizontal, Theme.Space.xs)
}
