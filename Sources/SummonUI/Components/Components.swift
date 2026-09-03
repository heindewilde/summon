import AppKit
import SwiftUI
import SummonKit

/// The colour-coded glyph that tells you at a glance what kind of thing a row is.
///
/// One component with two styles, because there were two — `KindBadge` drew a tinted
/// tile and `KindGlyph` drew a bare symbol, for the same semantic job, on different
/// surfaces, with nothing written down about which surface got which. The rule is:
///
/// - `.bare` in a content row, where the row already has a selection fill and a title
///   carrying weight, and a second filled shape would compete with both;
/// - `.tile` where the glyph *is* the content — a grid card, a 20pt tray row.
///
/// Kind colour is always the glyph and never the fill behind it. That is what lets it
/// share violet with the accent: the accent is only ever behind or around.
public struct KindIcon: View {
    public enum Style: Sendable { case bare, tile }

    public let kind: ItemKind
    public var style: Style = .bare
    public var size: CGFloat = 30
    public var isLocked = false

    public init(kind: ItemKind, style: Style = .bare, size: CGFloat = 30, isLocked: Bool = false) {
        self.kind = kind
        self.style = style
        self.size = size
        self.isLocked = isLocked
    }

    private var symbol: some View {
        Image(systemName: isLocked ? "lock.fill" : kind.symbolName)
            .font(.system(size: style == .tile ? size * 0.44 : size,
                          weight: style == .tile ? .medium : .regular))
            .foregroundStyle(isLocked ? Theme.tertiaryText : Theme.color(for: kind))
            // The one coloured thing in a row, so it is the one thing allowed to emit.
            // A flat coloured glyph on a dark ground reads as ink; a lit one reads as
            // an object, which is the difference the icon trades on.
            .glow(isLocked ? .clear : Theme.color(for: kind), radius: 5, strength: 0.45)
    }

    public var body: some View {
        Group {
            switch style {
            case .tile:
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .fill(Theme.color(for: kind).opacity(0.16))
                    .overlay { symbol }
                    .frame(width: size, height: size)
            case .bare:
                symbol.frame(width: Theme.Icon.slot, height: Theme.Icon.slot)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The tile style, under the name four call sites already use.
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
        KindIcon(kind: kind, style: .tile, size: size, isLocked: isLocked)
    }
}

/// Renders a title with the characters that matched the query picked out, so it is
/// obvious *why* a result is in the list.
///
/// The emphasis is monochrome: matched runs go bolder and up to the primary tier
/// while the rest sits at secondary. Raycast highlights nothing at all, but on a
/// fuzzy query like "invtm" that leaves the only cue for why a surprising row is in
/// the list — and a row you cannot explain reads as a bug. Weight and tier carry it
/// without reintroducing a hue.
public struct HighlightedTitle: View {
    public let text: String
    public let positions: [Int]
    public var font: Font = Theme.Typography.title

    public init(text: String, positions: [Int], font: Font = Theme.Typography.title) {
        self.text = text
        self.positions = positions
        self.font = font
    }

    public var body: some View {
        Text(attributed)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        // Nothing matched — an empty query, or a body-only hit — so the title is not
        // being explained and reads at full strength.
        guard !positions.isEmpty else {
            var plain = AttributedString(text)
            plain.foregroundColor = Theme.primaryText
            return plain
        }

        let characters = Array(text)
        let matched = Set(positions)

        // Built run by run: AttributedString indices are not integer offsets, and
        // walking them per character is both slower and easier to get wrong.
        var result = AttributedString()
        var buffer = ""
        var bufferMatched = matched.contains(0)

        func flush() {
            guard !buffer.isEmpty else { return }
            var run = AttributedString(buffer)
            run.foregroundColor = bufferMatched ? Theme.primaryText : Theme.secondaryText
            run.font = bufferMatched ? font.weight(.semibold) : font
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
            .font(Theme.Typography.micro.weight(.medium))
            // Was `Color.white` on a `Theme.primaryText` fill — which is white on near
            // black in light, and white on near white in dark. Accidentally right once.
            .foregroundStyle(isActive ? Theme.onAccent : Theme.secondaryText)
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
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Theme.hairline, in: .rect(cornerRadius: 4))
            Text(label)
                .font(Theme.Typography.micro)
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
                .font(Theme.Icon.regular.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.text)
                    .font(Theme.Typography.body.weight(.medium))
                if let detail = toast.detail {
                    Text(detail)
                        .font(Theme.Typography.caption)
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
        case .neutral: Theme.primaryText
        case .success: Theme.success
        // Was secondaryText, which made a warning indistinguishable from a neutral
        // message — the tone existed but said nothing.
        case .warning: Theme.warning
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
                .font(Theme.Icon.hero.weight(.light))
                .foregroundStyle(Theme.primaryText.opacity(0.7))
                .padding(.bottom, 2)
            Text(title)
                .font(Theme.Typography.heading.weight(.semibold))
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primaryText)
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

    /// Seeded synchronously from the cache, so an already-decoded thumbnail paints on
    /// the first frame and never flickers through the glyph placeholder.
    @State private var image: NSImage?

    public var body: some View {
        Group {
            if !isLocked, let image {
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
        .onAppear { if image == nil { image = ThumbnailCache.shared.cached(itemID) } }
        .task(id: itemID) {
            guard !isLocked, image == nil, let url = thumbnailURL else { return }
            image = await ThumbnailCache.shared.image(for: itemID, url: url, pointSize: size)
        }
    }
}

/// A subtle, non-alarming indication that something is protected.
public struct LockPill: View {
    public var text: String = "Locked"
    public init(text: String = "Locked") { self.text = text }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(Theme.Icon.micro.weight(.bold))
            Text(text).font(Theme.Icon.small.weight(.medium))
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        // `Theme.selection` until the accent landed, at which point a locked item
        // started wearing the colour that means "this is the row you are on".
        .background(Theme.surface, in: .capsule)
    }
}

/// A glass ground for a window's columns.
///
/// The panel had one of these all along and the library window had nothing — it took
/// the system's opaque window background, which is why the accent and the bloom
/// arrived everywhere except the surface people spend the most time in.
public struct GlassBackground: View {
    public var material: NSVisualEffectView.Material
    public var bloom: Double
    public var tint: Color

    public init(material: NSVisualEffectView.Material = .underWindowBackground,
                bloom: Double = 1, tint: Color = Theme.chrome) {
        self.material = material
        self.bloom = bloom
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            VisualEffectBackground(material: material, blending: .behindWindow)
            LinearGradient(colors: [tint.opacity(0.88), tint],
                           startPoint: .top, endPoint: .bottom)
            if bloom > 0 { Bloom(intensity: bloom) }
        }
        .ignoresSafeArea()
    }
}

/// Blurred backdrop that reads correctly in both appearances.
public struct PanelBackground: View {
    public init() {}
    public var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
            // Graded, not flat. A single fill is a rectangle of colour; a surface that
            // is fractionally lighter at the top has a direction and therefore a form.
            LinearGradient(colors: [Theme.chrome.opacity(0.88), Theme.chrome],
                           startPoint: .top, endPoint: .bottom)
            // The bloom. A gradient used to sit here and was removed for saying nothing
            // — it was a decorative wash that made the top of the list a different
            // colour from the bottom. This one is not that: it is the light the mark is
            // drawn in, and it is the reason the panel belongs to the same app as the
            // icon rather than merely pointing at it with an accent.
            Bloom()
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
            run.foregroundColor = Theme.primaryText
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
