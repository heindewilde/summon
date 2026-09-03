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
    @State private var rootTargeted = false

    public init(model: AppModel) { self.model = model }

    static let rowHeight: CGFloat = 26

    public var body: some View {
        // Read once per body rather than once per row: each of these used to walk
        // every snapshot in the library, four times over, on every redraw — and a
        // drag redraws continuously.
        let counts = model.sidebarCounts

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header("Library")
                row(.all, "All Items", "square.grid.2x2", count: counts.all)
                row(.recents, "Recents", "clock", count: counts.recents)
                row(.pinned, "Pinned", "pin", count: counts.pinned)
                if model.vault.isConfigured {
                    row(.locked, "Sensitive", "lock", count: counts.sensitive)
                }
                row(.clipboard, "Clipboard", "doc.on.clipboard",
                    count: model.clipboard.entries.count)

                header("Folders")
                ForEach(model.sidebarFolderRows) { entry in
                    FolderRow(model: model, entry: entry, renameText: $renameText)
                }
                newFolderButton

                let tags = model.store.tagsInUse()
                if !tags.isEmpty {
                    header("Tags")
                    ForEach(tags, id: \.id) { tag in
                        TagRow(model: model, tag: tag, renameText: $renameText)
                    }
                }

                header("Types")
                ForEach(ItemKind.allCases.filter { $0 != .richText }, id: \.self) { kind in
                    let count = counts.kinds[kind] ?? 0
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
        // folder, a nested folder could be nested deeper but never dragged back out,
        // and a filed item could never be unfiled.
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(rootTargeted ? Theme.selection : .clear)
        }
        .onDrop(of: SummonDragType.all,
                delegate: RootFolderDropDelegate(model: model, isTargeted: $rootTargeted))
        .help("Drag a folder or an item here to take it out of its folder")
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

/// One tag in the sidebar.
///
/// Its own view rather than the plain row helper, because a tag can be renamed and
/// deleted like a folder can — and it was the one thing in the sidebar you could
/// only edit by retyping it on every item that had it.
struct TagRow: View {
    @Bindable var model: AppModel
    let tag: SummonTag
    @Binding var renameText: String

    @FocusState private var nameFocused: Bool

    private var isSelected: Bool { model.sidebarSelection == .tag(tag.name) }
    private var isRenaming: Bool { model.renamingTagID == tag.id }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "number")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 16)

            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { model.renamingTagID = nil }
                    .onAppear { renameText = tag.name; nameFocused = true }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
            } else {
                // The name only: the icon column already carries the "#".
                Text(tag.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.xs)

            let count = (tag.items ?? []).count
            if count > 0 {
                Text("\(count)")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: SidebarView.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isSelected ? Theme.selection : .clear)
        }
        .contentShape(.rect)
        .onTapGesture { model.sidebarSelection = .tag(tag.name) }
        .contextMenu {
            Button("Rename") {
                // One rename at a time: both rows share the sidebar's text buffer, so
                // two open fields would edit the same string.
                model.renamingFolderID = nil
                renameText = tag.name
                model.renamingTagID = tag.id
            }
            Divider()
            Button("Delete Tag", role: .destructive) { model.deleteTag(tag) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((tag.items ?? []).isEmpty
                            ? tag.name : "\(tag.name), \((tag.items ?? []).count) items")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func commitRename() {
        guard isRenaming else { return }
        model.renameTag(tag, to: renameText)
        model.renamingTagID = nil
    }
}

/// One folder in the tree.
///
/// Driven by a plain value, not a SwiftData folder. A drag re-evaluates this view
/// many times a second, and reaching into the model graph for a name, an icon and a
/// recursive item count on every one of those was most of what made dragging feel
/// heavy.
struct FolderRow: View {
    @Bindable var model: AppModel
    let entry: SidebarFolderRow
    @Binding var renameText: String

    @State private var pickingIcon = false
    @FocusState private var nameFocused: Bool

    private var isSelected: Bool { model.sidebarSelection == .folder(entry.id) }
    private var dropZone: FolderDropZone? {
        model.folderDropTarget?.folderID == entry.id ? model.folderDropTarget?.zone : nil
    }
    private var isRenaming: Bool { model.renamingFolderID == entry.id }
    private var folder: SummonFolder? { model.store.folder(id: entry.id) }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button { model.toggleFolderCollapsed(entry.id) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .rotationEffect(.degrees(entry.isCollapsed ? 0 : 90))
                    .frame(width: 12, height: 12)
                    .contentShape(.rect)
                    .opacity(entry.hasChildren ? 1 : 0)
            }
            .buttonStyle(.plain)
            .disabled(!entry.hasChildren)
            .accessibilityHidden(!entry.hasChildren)
            .accessibilityLabel(entry.isCollapsed ? "Expand" : "Collapse")

            Button { pickingIcon = true } label: {
                Image(systemName: entry.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.folderColor(entry.colorName))
                    .frame(width: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Change icon")
            .accessibilityLabel("Change the icon for \(entry.name)")
            .popover(isPresented: $pickingIcon, arrowEdge: .trailing) {
                if let folder {
                    FolderIconPicker(model: model, folder: folder, isPresented: $pickingIcon)
                }
            }

            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { model.renamingFolderID = nil }
                    .onAppear { renameText = entry.name; nameFocused = true }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
            } else {
                Text(entry.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.xs)

            if entry.isSensitive {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .accessibilityHidden(true)
            }
            if entry.itemCount > 0 {
                Text("\(entry.itemCount)")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 14 + Theme.Space.xs)
        .padding(.trailing, Theme.Space.xs)
        .frame(height: SidebarView.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                // A fill means the drop goes *inside* this folder.
                .fill(dropZone == .into ? Theme.selection
                      : (isSelected ? Theme.selection : .clear))
        }
        // A line means the drop goes *beside* it.
        .overlay(alignment: .top) { if dropZone == .before { DropLine() } }
        .overlay(alignment: .bottom) { if dropZone == .after { DropLine() } }
        .contentShape(.rect)
        .onTapGesture { model.sidebarSelection = .folder(entry.id) }
        .onDrag {
            model.sidebarSelection = .folder(entry.id)
            let provider = NSItemProvider()
            provider.registerSummonID(entry.id, as: SummonDragType.folder)
            // A readable fallback, so dragging a folder into a text field or another
            // app leaves its name rather than a blob of nothing.
            provider.registerObject(entry.name as NSString, visibility: .all)
            provider.suggestedName = entry.name
            return provider
        }
        .onDrop(of: FolderDropTypes,
                delegate: FolderDropDelegate(folder: folderForDrop, model: model,
                                             rowHeight: SidebarView.rowHeight))
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.itemCount > 0 ? "\(entry.name), \(entry.itemCount) items"
                                                : entry.name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The drop delegate needs a folder up front. A row whose folder has just been
    /// deleted is about to disappear anyway; a placeholder keeps the type honest
    /// until it does, and every operation on it resolves by id first.
    private var folderForDrop: SummonFolder {
        folder ?? SummonFolder(id: entry.id, name: entry.name)
    }

    private func commitRename() {
        guard isRenaming, let folder else { return }
        model.store.renameFolder(folder, to: renameText)
        model.renamingFolderID = nil
    }

    @ViewBuilder
    private var menu: some View {
        Button("Rename") {
            model.renamingTagID = nil
            renameText = entry.name
            model.renamingFolderID = entry.id
        }
        Button("Change Icon…") { pickingIcon = true }
        Button("New Folder Inside") {
            guard let folder else { return }
            let child = model.store.createFolder(name: "New Folder", parent: folder)
            model.sidebarSelection = .folder(child.id)
            model.renamingFolderID = child.id
        }
        Button("Add Files…") { model.presentImportPanel(into: folder) }
        Divider()
        Button(folder?.isSensitive == true ? "Remove Sensitivity" : "Mark as Sensitive") {
            guard let folder else { return }
            model.setFolderSensitive(folder, !folder.isSensitive)
        }
        Divider()
        Button("Delete Folder", role: .destructive) {
            guard let folder else { return }
            model.store.deleteFolder(folder)
            model.runSearch()
        }
    }
}

/// An insertion indicator.
///
/// Quiet on purpose: a 2pt bar of near-white was the loudest thing on screen for
/// something that only says "the drop goes here".
struct DropLine: View {
    var body: some View {
        Capsule()
            .fill(Theme.secondaryText.opacity(0.55))
            .frame(height: 1.5)
            .padding(.horizontal, Theme.Space.xs)
    }
}
