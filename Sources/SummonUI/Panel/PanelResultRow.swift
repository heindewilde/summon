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
        HStack(spacing: Theme.Space.s) {
            KindGlyph(kind: item.kind, isLocked: item.isLocked)

            HighlightedTitle(text: item.title, positions: result.titlePositions)
                .layoutPriority(2)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .accessibilityLabel("Pinned")
            }
            if item.hasPlaceholders {
                Image(systemName: "square.dashed.inset.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Has fill-in fields")
            }

            Text(item.previewLine)
                .font(Theme.Typography.subtitle)
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: Theme.Space.s)

            if item.isLocked { LockPill() }

            Text(item.kind.displayName)
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize()

            // Drawn only where it is genuinely bound. Rendering ⌘10 or a badge with no
            // handler behind it is how the old row promised something the app never did.
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 22, alignment: .trailing)
            } else {
                Spacer().frame(width: 22)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isSelected ? Theme.selection : .clear)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onActivate)
        .onDrag { dragProvider() ?? NSItemProvider() }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin",
                   action: onTogglePin)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var accessibilityLabel: String {
        var parts = [item.title, item.kind.displayName]
        if item.isPinned { parts.append("pinned") }
        if item.isLocked { parts.append("locked") }
        if !item.folderPath.isEmpty { parts.append("in \(item.folderLabel)") }
        return parts.joined(separator: ", ")
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
