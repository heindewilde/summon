import AppKit
import SwiftUI
import SummonKit

/// The colour-coded glyph that tells you at a glance what kind of thing a row is.
public struct KindBadge: View {
    public let kind: ItemKind
    public var size: CGFloat = 30
    public var isLocked = false

    public init(kind: ItemKind, size: CGFloat = 30, isLocked: Bool = false) {
        self.kind = kind
        self.size = size
        self.isLocked = isLocked
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(Theme.color(for: kind).opacity(0.16))
            .overlay {
                Image(systemName: isLocked ? "lock.fill" : kind.symbolName)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(Theme.color(for: kind))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Renders a title with the characters that matched the query picked out, so it is
/// obvious *why* a result is in the list.
public struct HighlightedTitle: View {
    public let text: String
    public let positions: [Int]
    public var font: Font = .system(size: 13, weight: .medium)

    public init(text: String, positions: [Int], font: Font = .system(size: 13, weight: .medium)) {
        self.text = text
        self.positions = positions
        self.font = font
    }

    public var body: some View {
        Text(attributed)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var attributed: AttributedString {
        let characters = Array(text)
        guard !positions.isEmpty else { return AttributedString(text) }
        let matched = Set(positions)

        // Built run by run: AttributedString indices are not integer offsets, and
        // walking them per character is both slower and easier to get wrong.
        var result = AttributedString()
        var buffer = ""
        var bufferMatched = matched.contains(0)

        func flush() {
            guard !buffer.isEmpty else { return }
            var run = AttributedString(buffer)
            if bufferMatched {
                run.foregroundColor = Theme.accent
                run.font = .system(size: 13, weight: .bold)
            }
            result.append(run)
            buffer = ""
        }

        for (offset, character) in characters.enumerated() {
            let isMatch = matched.contains(offset)
            if isMatch != bufferMatched {
                flush()
                bufferMatched = isMatch
            }
            buffer.append(character)
        }
        flush()
        return result
    }
}

public struct TagChip: View {
    public let name: String
    public var isActive = false
    public init(name: String, isActive: Bool = false) {
        self.name = name
        self.isActive = isActive
    }

    public var body: some View {
        Text("#\(name)")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Theme.secondaryText)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, 2)
            .background(isActive ? Theme.accent : Theme.hairline, in: .capsule)
    }
}

/// A keyboard hint in the panel footer. The panel teaches its own shortcuts.
public struct KeyHint: View {
    public let keys: String
    public let label: String
    public init(_ keys: String, _ label: String) {
        self.keys = keys
        self.label = label
    }

    public var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Theme.hairline, in: .rect(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(keys)")
    }
}

public struct ToastView: View {
    public let toast: Toast
    public init(toast: Toast) { self.toast = toast }

    public var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: toast.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.text)
                    .font(.system(size: 12.5, weight: .medium))
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch toast.tone {
        case .neutral: Theme.accent
        case .success: Theme.success
        case .warning: Theme.spark
        case .danger: Theme.danger
        }
    }
}

/// Empty states are written, not generated: each one says what to do next.
public struct EmptyStateView: View {
    public let symbol: String
    public let title: String
    public let message: String
    public var action: (label: String, run: () -> Void)?

    public init(symbol: String, title: String, message: String,
                action: (label: String, run: () -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.7))
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.l)
    }
}

/// A thumbnail if one exists, the type glyph otherwise. Never a broken image box.
public struct ThumbnailView: View {
    public let itemID: UUID
    public let kind: ItemKind
    public let isLocked: Bool
    public let thumbnailURL: URL?
    public var size: CGFloat

    public init(itemID: UUID, kind: ItemKind, isLocked: Bool, thumbnailURL: URL?, size: CGFloat = 30) {
        self.itemID = itemID
        self.kind = kind
        self.isLocked = isLocked
        self.thumbnailURL = thumbnailURL
        self.size = size
    }

    public var body: some View {
        Group {
            if !isLocked, let url = thumbnailURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.29, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
            } else {
                KindBadge(kind: kind, size: size, isLocked: isLocked)
            }
        }
        .id(itemID)
    }
}

/// A subtle, non-alarming indication that something is protected.
public struct LockPill: View {
    public var text: String = "Locked"
    public init(text: String = "Locked") { self.text = text }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 8.5, weight: .bold))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.spark)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Theme.sparkWash, in: .capsule)
    }
}

/// Blurred backdrop that reads correctly in both appearances.
public struct PanelBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
            LinearGradient(
                colors: [Theme.accent.opacity(0.10), .clear],
                startPoint: .topLeading, endPoint: .bottom
            )
        }
    }
}

public struct VisualEffectBackground: View {
    public var material: NSVisualEffectView.Material
    public var blending: NSVisualEffectView.BlendingMode
    @Environment(\.isSnapshotting) private var isSnapshotting

    public init(material: NSVisualEffectView.Material, blending: NSVisualEffectView.BlendingMode) {
        self.material = material
        self.blending = blending
    }

    public var body: some View {
        if isSnapshotting {
            Color(nsColor: .dyn(light: .srgb(0.97, 0.97, 0.98), dark: .srgb(0.15, 0.15, 0.17)))
        } else {
            VisualEffectRepresentable(material: material, blending: blending)
        }
    }
}

struct VisualEffectRepresentable: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}


/// Renders snippet text with `{{placeholders}}` picked out, so it is obvious at a
/// glance which parts will be filled in and which are already final.
public struct PlaceholderHighlightedText: View {
    public let text: String
    public var size: CGFloat

    public init(text: String, size: CGFloat = 12) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Text(attributed)
            .font(.system(size: size))
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var buffer = ""
        var token = ""
        var inToken = false
        var index = text.startIndex

        func flushLiteral() {
            guard !buffer.isEmpty else { return }
            result.append(AttributedString(buffer))
            buffer = ""
        }

        func flushToken() {
            guard !token.isEmpty else { return }
            var run = AttributedString(token)
            run.foregroundColor = Theme.accent
            run.font = .system(size: size, weight: .medium)
            result.append(run)
            token = ""
        }

        while index < text.endIndex {
            let rest = text[index...]
            if !inToken, rest.hasPrefix("{{") {
                flushLiteral()
                inToken = true
                token = "{{"
                index = text.index(index, offsetBy: 2)
                continue
            }
            if inToken, rest.hasPrefix("}}") {
                token += "}}"
                flushToken()
                inToken = false
                index = text.index(index, offsetBy: 2)
                continue
            }
            if inToken { token.append(text[index]) } else { buffer.append(text[index]) }
            index = text.index(after: index)
        }
        // An unterminated "{{" is literal text, not a placeholder.
        if inToken { buffer += token; token = "" }
        flushLiteral()
        return result
    }
}
