import AppKit
import SummonKit
import SwiftUI

/// The one row.
///
/// The panel, the library list and the menu bar all render this, so their density
/// cannot drift apart again — which it had: three surfaces, three heights, three
/// type scales, three ideas of what a subtitle was for.
///
/// A single 40pt line. The subtitle carries the body preview rather than the folder
/// path, because two replies both called "Follow-up" are told apart by what is in
/// them; the folder is in the preview pane and the detail view, where there is room.
public struct LibraryRow: View {
    public let item: ItemSnapshot
    public var titlePositions: [Int] = []
    public var isSelected: Bool = false
    /// The ⌘-number, when this surface binds one. Nil draws nothing — a badge with
    /// no handler behind it is a promise the app does not keep.
    public var shortcutIndex: Int?
    /// Trailing text where the panel shows the kind. The library shows the date.
    public var trailingText: String?
    /// Shown on hover or while selected. Nil in the panel, where ↩ already copies.
    public var onCopy: (() -> Void)?

    public init(item: ItemSnapshot,
                titlePositions: [Int] = [],
                isSelected: Bool = false,
                shortcutIndex: Int? = nil,
                trailingText: String? = nil,
                onCopy: (() -> Void)? = nil) {
        self.item = item
        self.titlePositions = titlePositions
        self.isSelected = isSelected
        self.shortcutIndex = shortcutIndex
        self.trailingText = trailingText
        self.onCopy = onCopy
    }

    @State private var hovering = false
    @State private var justCopied = false

    /// Measured, because the same row is asked to live in a 750pt panel and a 290pt
    /// library column. Below this there is no honest room for a subtitle, and
    /// squeezing one in shreds the title and renders the preview as a single letter.
    private static let subtitleThreshold: CGFloat = 430

    @State private var width: CGFloat = 0
    private var showsSubtitle: Bool { width >= Self.subtitleThreshold }

    public var body: some View {
        HStack(spacing: Theme.Space.s) {
            KindGlyph(kind: item.kind, isLocked: item.isLocked)

            HighlightedTitle(text: item.title, positions: titlePositions)
                .layoutPriority(2)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .accessibilityHidden(true)
            }
            if item.hasPlaceholders {
                Image(systemName: "square.dashed.inset.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
                    .accessibilityHidden(true)
                    .help("Has fill-in fields")
            }

            if showsSubtitle {
                Text(item.previewLine)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }

            Spacer(minLength: Theme.Space.s)

            if item.isLocked { LockPill() }

            if let onCopy, !item.isLocked, hovering || isSelected || justCopied {
                Button {
                    onCopy()
                    justCopied = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1100))
                        justCopied = false
                    }
                } label: {
                    // Confirmation lands where you clicked, so nothing else on screen
                    // has to move to tell you it worked.
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(justCopied ? Theme.success : Theme.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Copy")
                .accessibilityLabel(justCopied ? "Copied" : "Copy \(item.title)")
            }

            if let trailingText {
                Text(trailingText)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize()
            }

            if let shortcutIndex, shortcutIndex < 9 {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.faintText)
                    .frame(width: 22, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: Theme.rowHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onHover { hovering = $0 }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(hovering && !isSelected ? Theme.rowHover : .clear)
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isSelected ? Theme.selection : .clear)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Spoken instead of the visual row. Reads in the order the eye takes it, and
    /// says the things the glyphs mean rather than describing the glyphs.
    private var accessibilityLabel: String {
        var parts = [item.title, item.kind.displayName]
        if item.isPinned { parts.append("pinned") }
        if item.isLocked { parts.append("locked") }
        if item.hasPlaceholders { parts.append("has fill-in fields") }
        if !item.folderPath.isEmpty { parts.append("in \(item.folderLabel)") }
        if let shortcutIndex, shortcutIndex < 9 { parts.append("command \(shortcutIndex + 1)") }
        return parts.joined(separator: ", ")
    }
}
