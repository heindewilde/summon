import AppKit
import SwiftUI
import SummonKit

/// One result. A single 40pt line: glyph, title, inline subtitle, then the type and
/// its ⌘-number, right-aligned.
///
/// The subtitle carries the body preview rather than the folder path, because two
/// canned replies called "Follow-up" are told apart by what is in them, not by where
/// they live — the folder is in the preview pane, where there is room for it.
public struct PanelResultRow: View {
    public let result: SearchResult
    public let isSelected: Bool
    public let index: Int
    public let onActivate: () -> Void
    public let onTogglePin: () -> Void
    public let dragProvider: () -> NSItemProvider?

    public init(result: SearchResult, isSelected: Bool, index: Int,
                onActivate: @escaping () -> Void, onTogglePin: @escaping () -> Void,
                dragProvider: @escaping () -> NSItemProvider? = { nil }) {
        self.result = result
        self.isSelected = isSelected
        self.index = index
        self.onActivate = onActivate
        self.onTogglePin = onTogglePin
        self.dragProvider = dragProvider
    }

    private var item: ItemSnapshot { result.item }

    public var body: some View {
        LibraryRow(item: item,
                   titlePositions: result.titlePositions,
                   isSelected: isSelected,
                   shortcutIndex: index,
                   trailingText: item.kind.displayName)
            .onTapGesture(perform: onActivate)
            .onDrag { dragProvider() ?? NSItemProvider() }
            .contextMenu {
                Button(item.isPinned ? "Unpin" : "Pin",
                       systemImage: item.isPinned ? "pin.slash" : "pin",
                       action: onTogglePin)
            }
    }

}

/// The bare type glyph. No tinted tile behind it — in a monochrome list the symbol is
/// the only coloured element, and a filled capsule would compete with the selection.
public struct KindGlyph: View {
    public let kind: ItemKind
    public var isLocked = false
    public var size: CGFloat = 15

    public init(kind: ItemKind, isLocked: Bool = false, size: CGFloat = 15) {
        self.kind = kind
        self.isLocked = isLocked
        self.size = size
    }

    public var body: some View {
        Image(systemName: isLocked ? "lock.fill" : kind.symbolName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(isLocked ? Theme.tertiaryText : Theme.color(for: kind))
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
