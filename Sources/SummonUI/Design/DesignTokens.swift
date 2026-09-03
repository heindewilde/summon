import AppKit
import SwiftUI
import SummonKit

/// The single source of Summon's visual identity.
///
/// The chrome is deliberately monochrome. Colour in a launcher should mean something —
/// what kind of thing a row is, or that an action is destructive — and a tinted
/// selection bar or a gradient header means nothing, so it earns no colour. What is
/// left is a small set of near-neutral surfaces separated by 3–6% steps rather than
/// the heavy contrast a naive dark theme reaches for, hairline rules, and type that
/// carries the hierarchy on weight and tier alone.
///
/// Both appearances are defined for every value; none is defined only for dark.
public enum Theme {

    // MARK: - Surfaces

    /// The panel and window ground, layered over the vibrancy material.
    public static let chrome = Color(nsColor: .dyn(light: .srgb(0.97, 0.97, 0.97, 0.72),
                                                  dark: .srgb(0.11, 0.11, 0.12, 0.72)))
    /// Sheets and popovers that sit above the chrome — the ⌘K action panel.
    public static let raised = Color(nsColor: .dyn(light: .srgb(1, 1, 1, 0.98),
                                                   dark: .srgb(0.145, 0.145, 0.157, 0.98)))
    /// The selected row. Neutral: selection is position, not category.
    public static let selection = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.06),
                                                      dark: .srgb(1, 1, 1, 0.08)))
    public static let rowHover = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.035),
                                                     dark: .srgb(1, 1, 1, 0.05)))
    public static let hairline = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.08),
                                                     dark: .srgb(1, 1, 1, 0.08)))
    /// A field or well inset into the chrome.
    public static let surface = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.04),
                                                    dark: .srgb(1, 1, 1, 0.05)))
    public static let surfaceRaised = Color(nsColor: .dyn(light: .srgb(1, 1, 1, 0.95),
                                                          dark: .srgb(1, 1, 1, 0.08)))

    // MARK: - Text

    // Alphas are chosen to clear WCAG AA against `chrome`, not by eye. The values
    // are asserted in ContrastTests — the first draft of this palette put the row's
    // body preview at 3.20:1 in dark and 2.65:1 in light, both under the 4.5:1 bar
    // for text this size, and it looked fine.
    public static let primaryText = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.88),
                                                        dark: .srgb(1, 1, 1, 0.95)))
    public static let secondaryText = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.64),
                                                          dark: .srgb(1, 1, 1, 0.66)))
    public static let tertiaryText = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.58),
                                                         dark: .srgb(1, 1, 1, 0.50)))
    /// Decoration only — the ⌘-number badge, a disabled glyph. Never body text; held
    /// to the 3:1 non-text bar rather than 4.5:1.
    public static let faintText = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.45),
                                                      dark: .srgb(1, 1, 1, 0.36)))

    // MARK: - Status
    //
    // Semantic, not decorative: these three say "this will destroy something",
    // "this worked" and "this needs your attention". Those are the jobs colour is
    // genuinely best at, so they survive the monochrome rule.

    public static let danger = Color(nsColor: .dyn(light: .srgb(0.78, 0.18, 0.18),
                                                   dark: .srgb(1.00, 0.42, 0.40)))
    // The two light values are darker than they look like they should be. They were
    // 0.10/0.55/0.30 and 0.72/0.47/0.04, which measure 3.93:1 and 3.38:1 on the light
    // ground — both under the 4.5:1 bar, both shipped, and neither catchable by the old
    // contrast test, which only ever knew about the four text tiers.
    public static let success = Color(nsColor: .dyn(light: .srgb(0.091, 0.503, 0.275),
                                                    dark: .srgb(0.36, 0.85, 0.55)))
    public static let warning = Color(nsColor: .dyn(light: .srgb(0.605, 0.395, 0.034),
                                                    dark: .srgb(1.00, 0.72, 0.28)))

    // MARK: - Rhythm

    /// A 4pt grid. The previous scale (3/6/10/16/24/36) had irregular jumps, which is
    /// why call sites had grown `Space.s + 2` and bare `7`s to hit the spacing they
    /// actually wanted.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Radius {
        public static let small: CGFloat = 5
        public static let medium: CGFloat = 8
        public static let large: CGFloat = 10
        public static let panel: CGFloat = 10
    }

    /// One row height, shared by the panel, the main window and the menu bar, so the
    /// three surfaces cannot drift apart.
    public static let rowHeight: CGFloat = 40

    // MARK: - Typography
    //
    // Named, because every call site used to hardcode `.system(size:)` — which is how
    // 9.5, 10, 10.5, 11, 12, 13, 16 and 20 all ended up in one panel.

    public enum Typography {
        public static let title = Font.system(size: 13)
        /// Matched characters. Emphasis by weight and tier, never by hue.
        public static let titleMatch = Font.system(size: 13, weight: .semibold)
        public static let subtitle = Font.system(size: 13)
        public static let meta = Font.system(size: 11)
        public static let section = Font.system(size: 11, weight: .semibold)
        public static let field = Font.system(size: 18)
        public static let key = Font.system(size: 11, weight: .medium)
        public static let body = Font.system(size: 12)
    }

    // MARK: - Motion
    //
    // Almost nothing moves. A result list that fades in row by row is slower to read
    // than one that is simply there, and the search behind it now completes in half a
    // millisecond — animating the result of that would be spending the win.
    // Result swaps, selection changes and scrolling are not animated at all.

    /// The panel edge appearing. The only entrance in the app.
    public static let panelIn = Animation.easeOut(duration: 0.12)
    /// The ⌘K sheet rising. The only other animation.
    public static let sheet = Animation.easeOut(duration: 0.14)
    /// Width change when the preview pane appears for an image or a PDF.
    public static let previewSplit = Animation.easeOut(duration: 0.10)

    // MARK: - Type colours
    //
    // Kept. These are the one place colour carries information — what kind of thing a
    // row is — and the glyph is the only coloured element in the chrome.

    public static func color(for kind: ItemKind) -> Color {
        switch kind {
        case .text: Color(nsColor: .dyn(light: .srgb(0.36, 0.25, 0.78), dark: .srgb(0.64, 0.55, 1.00)))
        case .richText: Color(nsColor: .dyn(light: .srgb(0.22, 0.36, 0.80), dark: .srgb(0.50, 0.66, 1.00)))
        case .image: Color(nsColor: .dyn(light: .srgb(0.05, 0.52, 0.52), dark: .srgb(0.33, 0.83, 0.80)))
        case .document: Color(nsColor: .dyn(light: .srgb(0.76, 0.44, 0.07), dark: .srgb(1.00, 0.71, 0.32)))
        case .file: Color(nsColor: .dyn(light: .srgb(0.36, 0.40, 0.48), dark: .srgb(0.66, 0.71, 0.80)))
        }
    }

    /// Named folder colours, kept small on purpose.
    public static let folderColorNames = ["violet", "blue", "teal", "green", "amber", "red", "graphite"]

    public static func folderColor(_ name: String) -> Color {
        switch name {
        case "blue": Color(nsColor: .dyn(light: .srgb(0.15, 0.40, 0.85), dark: .srgb(0.45, 0.66, 1.00)))
        case "teal": Color(nsColor: .dyn(light: .srgb(0.05, 0.52, 0.52), dark: .srgb(0.33, 0.83, 0.80)))
        case "green": Color(nsColor: .dyn(light: .srgb(0.15, 0.52, 0.26), dark: .srgb(0.42, 0.84, 0.53)))
        case "amber": Color(nsColor: .dyn(light: .srgb(0.76, 0.47, 0.05), dark: .srgb(1.00, 0.73, 0.30)))
        case "red": Color(nsColor: .dyn(light: .srgb(0.75, 0.20, 0.22), dark: .srgb(1.00, 0.47, 0.45)))
        case "graphite": Color(nsColor: .dyn(light: .srgb(0.36, 0.40, 0.46), dark: .srgb(0.68, 0.72, 0.78)))
        case "violet": Color(nsColor: .dyn(light: .srgb(0.36, 0.25, 0.78), dark: .srgb(0.64, 0.55, 1.00)))
        default: Color(nsColor: .dyn(light: .srgb(0.36, 0.40, 0.46), dark: .srgb(0.68, 0.72, 0.78)))
        }
    }
}

// MARK: - Colour helpers

extension NSColor {
    static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// One colour, correct in both appearances — never a value defined only for dark.
    static func dyn(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - Shared modifiers

public struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.Radius.medium
    var raised = false

    public func body(content: Content) -> some View {
        content
            .background(raised ? Theme.surfaceRaised : Theme.surface, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

public extension View {
    func cardBackground(radius: CGFloat = Theme.Radius.medium, raised: Bool = false) -> some View {
        modifier(CardBackground(radius: radius, raised: raised))
    }

    /// The panel entrance: a short fade and a scale small enough to read as the window
    /// arriving rather than as an animation you have to wait out.
    func summonTransition(isVisible: Bool, reduceMotion: Bool) -> some View {
        scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.99))
            .opacity(isVisible ? 1 : 0)
            .animation(reduceMotion ? .linear(duration: 0.01) : Theme.panelIn, value: isVisible)
    }
}
