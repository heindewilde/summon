import AppKit
import SummonKit
import SwiftUI

/// The ⌘K panel: every action for the selected item, searchable, anchored bottom-right.
///
/// A SwiftUI overlay inside the same window rather than a second `NSWindow` — a
/// non-activating panel spawning a child panel is where focus bugs live, and the key
/// routing already follows first responder, so it needs no window of its own.
public struct ActionMenu: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel) { self.model = model }

    private static let width: CGFloat = 300

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.hairline)

            switch model.overlay {
            case .actions: actionList
            case .prompt(let kind): promptField(kind)
            case .folderPicker: folderList
            case .confirmDelete: confirmDelete
            case .none: EmptyView()
            }
        }
        .frame(width: Self.width)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 22, y: 8)
        .padding(.trailing, Theme.Space.m)
        .padding(.bottom, 48)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Text(model.overlayTitle)
                .font(Theme.Typography.section)
                .foregroundStyle(Theme.tertiaryText)
                .tracking(0.5)
            Spacer()
            if let title = model.selectedResult?.item.title {
                Text(title)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 32)
    }

    // MARK: - Actions

    private var actionList: some View {
        VStack(spacing: 0) {
            SnapshotSafeScrollView {
                SnapshotSafeLazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.actionResults.enumerated()), id: \.element) { index, action in
                        actionRow(action, isSelected: index == model.actionSelectedIndex)
                    }
                }
                .padding(Theme.Space.xs)
            }
            .frame(maxHeight: 312)

            Divider().overlay(Theme.hairline)
            searchField(placeholder: "Search actions…", text: $model.actionQuery)
        }
    }

    private func actionRow(_ action: PanelActionID, isSelected: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: action.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(action.isDestructive ? Theme.danger : Theme.secondaryText)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(action.title)
                .font(Theme.Typography.title)
                .foregroundStyle(action.isDestructive ? Theme.danger : Theme.primaryText)

            Spacer(minLength: Theme.Space.s)

            // The hint is derived from the binding, so it cannot describe a key that
            // does not work.
            if let chord = PanelKeyMap.chord(for: action) {
                Text(chord.display)
                    .font(Theme.Typography.key)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isSelected ? Theme.selection : .clear)
        }
        .contentShape(.rect)
        .onTapGesture { model.run(action) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title
            + (PanelKeyMap.chord(for: action).map { ", \($0.display)" } ?? "")
            + (action.isDestructive ? ", destructive" : ""))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Rename / Add tag

    private func promptField(_ kind: PromptKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField(placeholder: kind.placeholder, text: $model.promptText)
            Divider().overlay(Theme.hairline)
            HStack {
                KeyHint("↩", kind == .rename ? "Rename" : "Add")
                Spacer()
                KeyHint("⎋", "Cancel")
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(height: 30)
        }
    }

    // MARK: - Move to folder

    private var folderList: some View {
        VStack(spacing: 0) {
            SnapshotSafeScrollView {
                SnapshotSafeLazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.folderChoices.enumerated()), id: \.element.id) { index, choice in
                        HStack(spacing: Theme.Space.s) {
                            Image(systemName: choice.id == nil ? "tray" : "folder")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(choice.label)
                                .font(Theme.Typography.title)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.Space.s)
                        .frame(height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(index == model.folderChoiceIndex ? Theme.selection : .clear)
                        }
                        .contentShape(.rect)
                        .onTapGesture {
                            model.folderChoiceIndex = index
                            model.perform(.runSelectedAction)
                        }
                    }
                }
                .padding(Theme.Space.xs)
            }
            .frame(maxHeight: 264)
        }
    }

    // MARK: - Delete

    private var confirmDelete: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Delete “\(model.selectedResult?.item.title ?? "this item")”?")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.primaryText)
            Text("This cannot be undone.")
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.secondaryText)
            HStack {
                KeyHint("↩", "Delete")
                Spacer()
                KeyHint("⎋", "Keep")
            }
            .padding(.top, Theme.Space.xs)
        }
        .padding(Theme.Space.m)
    }

    // MARK: - Shared field

    private func searchField(placeholder: String, text: Binding<String>) -> some View {
        PanelSearchField(
            text: text,
            placeholder: placeholder,
            fontSize: 13,
            focusToken: model.overlayFocusToken,
            route: { selector, isEmpty in
                model.routeFieldSelector(selector, fieldIsEmpty: isEmpty)
            }
        )
        .frame(height: 20)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
    }
}
