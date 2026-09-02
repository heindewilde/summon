import AppKit
import SwiftUI
import SummonKit

public struct PanelResultRow: View {
    public let result: SearchResult
    public let isSelected: Bool
    public let index: Int
    public let thumbnailURL: URL?
    public let onActivate: () -> Void
    public let onTogglePin: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(result: SearchResult, isSelected: Bool, index: Int, thumbnailURL: URL?,
                onActivate: @escaping () -> Void, onTogglePin: @escaping () -> Void) {
        self.result = result
        self.isSelected = isSelected
        self.index = index
        self.thumbnailURL = thumbnailURL
        self.onActivate = onActivate
        self.onTogglePin = onTogglePin
    }

    private var item: ItemSnapshot { result.item }

    public var body: some View {
        HStack(spacing: Theme.Space.s) {
            ThumbnailView(itemID: item.id, kind: item.kind, isLocked: item.isLocked,
                          thumbnailURL: thumbnailURL, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    HighlightedTitle(text: item.title, positions: result.titlePositions)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Theme.spark)
                            .accessibilityLabel("Pinned")
                    }
                    if item.hasPlaceholders {
                        Image(systemName: "square.dashed.inset.filled")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.accent)
                            .help("Has fill-in fields")
                    }
                    if item.isLocked { LockPill() }
                }

                HStack(spacing: Theme.Space.xs) {
                    if !item.folderPath.isEmpty {
                        Label(item.folderLabel, systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                    Text(item.previewLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: Theme.Space.xs)

            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.tertiaryText.opacity(0.6))
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(isSelected ? Theme.accentWash : .clear)
        }
        .overlay(alignment: .leading) {
            // A slim accent rail marks the selection without shouting.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.accent)
                .frame(width: 2.5, height: isSelected ? 22 : 0)
                .padding(.leading, 1)
                .animation(reduceMotion ? nil : Theme.quick, value: isSelected)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onActivate)
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
