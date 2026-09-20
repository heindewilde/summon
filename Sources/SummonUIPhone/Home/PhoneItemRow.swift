// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// One item, sized for a fingertip.
///
/// Not `LibraryRow`: that row shows its copy button on hover and ranks its density
/// against a 750pt panel. Here the whole row *is* the copy button — the summon moment
/// on a phone is "tap it, it's on the clipboard" — and the chevron beside it is the
/// only way to open the item, so the two actions never fight over the same pixels.
struct PhoneItemRow: View {
    let item: ItemSnapshot
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Button(action: onCopy) {
                HStack(spacing: Theme.Space.m) {
                    KindGlyph(kind: item.kind, isLocked: item.isLocked, size: 22)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(Theme.Typography.title.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(Theme.Typography.meta)
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Pinned")
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(item.title.isEmpty ? "untitled item" : item.title)")
            .accessibilityHint(item.isLocked ? "Locked. Unlock to copy." : "Copies to the clipboard")

            // A separate button, and a separate accessibility element: "open" and
            // "copy" are different intentions and a phone has no modifier key to tell
            // them apart.
            Button(action: onOpen) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.faintText)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }

    private var subtitle: String {
        if item.isLocked { return "Locked" }
        let preview = item.previewLine.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return preview.isEmpty ? item.kind.displayName : preview
    }
}
#endif
