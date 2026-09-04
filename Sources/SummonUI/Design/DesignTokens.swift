#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import SummonKit

/// The single source of Summon's visual identity.
///
/// One accent: the violet the app icon is drawn in. It marks **state** — what is
/// selected, what has the keyboard, where you are, and the one button that finishes a
/// sentence. Nothing else in the chrome is tinted.
///
/// This reverses 07d3a88, which took violet out on the grounds that a tinted selection
/// bar means nothing. That was right about decoration and wrong about state: with
/// everything neutral, "the row I am on" and "the row the pointer is over" sat two per
/// cent apart. The rule that survives is the one that mattered — colour must carry
/// information. Violet carries exactly one piece: this is where you are.
///
/// Violet is also `color(for: .text)` and `folderColor("violet")`, and that is allowed
/// because the two never take the same role:
///
/// - the accent is always **behind or around** — a fill, a ring, a rule;
/// - kind and folder colour are always **the thing itself** — a glyph, never a fill.
///
/// That split is load-bearing, not stylistic. A violet kind glyph on a *solid* violet
/// selection measures 1.00:1 — the same colour on itself, invisible. So the selection
/// fill is a tint and stays one; solid violet is for buttons and rings, where nothing
/// coloured sits on top. `ContrastTests` asserts all of it.
///
/// Both appearances are defined for every value; none is defined only for dark.
public enum Theme {

    // MARK: - Surfaces

    // The ground carries the identity, and for a long time it did not: the accent said
    // "you are here" while the surface under it stayed the same neutral grey a stock
    // utility ships with. These are violet-cast and deeper, so the app is *made of*
    // something rather than merely marked with it.

    /// The panel and window ground, layered over the vibrancy material.
    public static let chrome = Color(platform: .dyn(light: .srgb(0.965, 0.960, 0.995, 0.86),
                                                  dark: .srgb(0.043, 0.040, 0.063, 0.92)))
    /// Sheets and popovers that sit above the chrome — the ⌘K action panel.
    public static let raised = Color(platform: .dyn(light: .srgb(1, 0.995, 1, 0.96),
                                                   dark: .srgb(0.098, 0.090, 0.137, 0.94)))
    // MARK: - State
    //
    // The four states are deliberately different in kind, not just in strength, so
    // they cannot be mistaken for one another at a glance.

    /// Solid violet. The one button that finishes a sentence, a drop line, progress.
    /// Never a fill behind a kind glyph — see the note on this type.
    public static let accent = Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78),
                                                   dark: .srgb(0.64, 0.55, 1.00)))
    /// Ink on top of `accent`. The accent inverts between appearances — dark violet on
    /// light, light violet on dark — so what reads on it inverts too.
    public static let onAccent = Color(platform: .dyn(light: .srgb(1, 1, 1),
                                                     dark: .srgb(0.055, 0.055, 0.071)))

    /// The selected row: keys act on this. A tint, never solid.
    ///
    /// Stronger than it needed to be on a neutral ground: once the ground is itself
    /// violet-cast, a 14% violet fill on it is nearly the same colour, and selection
    /// stops reading. It is paired with `selectionEdge` for the same reason.
    public static let selection = Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78, 0.20),
                                                      dark: .srgb(0.68, 0.60, 1.00, 0.24)))
    /// The lit top edge of a selected row — the tell that a pane of glass is sitting
    /// on the surface rather than the surface having changed colour.
    public static let selectionEdge = Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78, 0.30),
                                                          dark: .srgb(0.86, 0.82, 1.00, 0.30)))
    /// Still selected, but the keyboard is in another pane. The old neutral selection,
    /// kept — this is the macOS convention, and in a three-pane window it is the only
    /// way to say which column the arrow keys belong to.
    public static let selectionInactive = Color(platform: .dyn(light: .srgb(0, 0, 0, 0.06),
                                                              dark: .srgb(1, 1, 1, 0.08)))
    /// Where you are in the navigation, which is not the same as what has focus.
    public static let navActive = Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78, 0.18),
                                                      dark: .srgb(0.64, 0.55, 1.00, 0.22)))
    /// The pointer is here. Stays neutral on purpose: hover follows the mouse, and a
    /// violet that chases the cursor across a list strobes.
    public static let rowHover = Color(platform: .dyn(light: .srgb(0, 0, 0, 0.035),
                                                     dark: .srgb(1, 1, 1, 0.05)))
    /// Keystrokes land in this control. One per screen, ever.
    public static let focusRing = Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78, 0.75),
                                                      dark: .srgb(0.64, 0.55, 1.00, 0.75)))
    /// The bloom: the icon's light, spread across a whole surface rather than pooled
    /// behind one object. This is the single biggest reason the onboarding looks like
    /// the icon and the rest of the app did not — the accent said where you were, but
    /// the ground it said it on was the same neutral grey any utility ships with.
    public static let bloom = Color(platform: .dyn(light: .srgb(0.42, 0.30, 0.92, 0.20),
                                                  dark: .srgb(0.52, 0.40, 1.00, 0.52)))

    /// The specular edge of glass: the thin bright line along a lit top edge. Without
    /// it a translucent fill is a flat tint, which is most of why the first pass at
    /// this read as "plain" — glass is edges and highlights, not transparency.
    public static let glassSheen = Color(platform: .dyn(light: .srgb(1, 1, 1, 0.90),
                                                       dark: .srgb(1, 0.99, 1, 0.24)))

    /// A drop lands here. Its own token because a drop target drawn with `selection`
    /// says "this folder is selected" instead — the same pixel, two meanings.
    public static let dropTarget = accent
    /// The lit edge of a pane of glass, which is why it is brighter than a hairline
    /// usually is: on a translucent surface an 8% rule disappears into the blur.
    public static let hairline = Color(platform: .dyn(light: .srgb(0.30, 0.24, 0.55, 0.14),
                                                     dark: .srgb(1, 0.99, 1, 0.13)))
    /// A field or well inset into the chrome. Violet-cast rather than neutral, so a
    /// well reads as part of the same material as everything around it.
    public static let surface = Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78, 0.055),
                                                    dark: .srgb(0.72, 0.66, 1.00, 0.075)))
    public static let surfaceRaised = Color(platform: .dyn(light: .srgb(1, 1, 1, 0.72),
                                                          dark: .srgb(0.78, 0.74, 1.00, 0.11)))

    // MARK: - Text

    // Alphas are chosen to clear WCAG AA against `chrome`, not by eye. The values
    // are asserted in ContrastTests — the first draft of this palette put the row's
    // body preview at 3.20:1 in dark and 2.65:1 in light, both under the 4.5:1 bar
    // for text this size, and it looked fine.
    public static let primaryText = Color(platform: .dyn(light: .srgb(0, 0, 0, 0.88),
                                                        dark: .srgb(1, 1, 1, 0.95)))
    public static let secondaryText = Color(platform: .dyn(light: .srgb(0, 0, 0, 0.64),
                                                          dark: .srgb(1, 1, 1, 0.66)))
    public static let tertiaryText = Color(platform: .dyn(light: .srgb(0, 0, 0, 0.58),
                                                         dark: .srgb(1, 1, 1, 0.50)))
    /// Decoration only — the ⌘-number badge, a disabled glyph. Never body text; held
    /// to the 3:1 non-text bar rather than 4.5:1.
    public static let faintText = Color(platform: .dyn(light: .srgb(0, 0, 0, 0.45),
                                                      dark: .srgb(1, 1, 1, 0.36)))

    // MARK: - Status
    //
    // Semantic, not decorative: these three say "this will destroy something",
    // "this worked" and "this needs your attention". Those are the jobs colour is
    // genuinely best at, so they survive the monochrome rule.

    public static let danger = Color(platform: .dyn(light: .srgb(0.78, 0.18, 0.18),
                                                   dark: .srgb(1.00, 0.42, 0.40)))
    // The two light values are darker than they look like they should be. They were
    // 0.10/0.55/0.30 and 0.72/0.47/0.04, which measure 3.93:1 and 3.38:1 on the light
    // ground — both under the 4.5:1 bar, both shipped, and neither catchable by the old
    // contrast test, which only ever knew about the four text tiers.
    public static let success = Color(platform: .dyn(light: .srgb(0.091, 0.503, 0.275),
                                                    dark: .srgb(0.36, 0.85, 0.55)))
    public static let warning = Color(platform: .dyn(light: .srgb(0.605, 0.395, 0.034),
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
    /// The sidebar's row. Denser than a content row but not cramped: it sits beside
    /// the library list, and once that went roomy a 26pt row next to a 48pt one read
    /// as squeezed rather than as compact.
    public static let rowCompact: CGFloat = 32
    /// Action-menu and popover rows: between a list row and a sidebar row.
    public static let rowMenu: CGFloat = 32
    /// The library's row. Roomier than the panel's on purpose: a launcher is passed
    /// through and wants results on screen, a library is sat in and wants air.
    public static let rowRoomy: CGFloat = 48

    /// A row you hit with a fingertip.
    ///
    /// 44pt is Apple's minimum target and the floor rather than the choice; 52 gives
    /// the same breathing room around a two-line row that `rowRoomy` gives a pointer,
    /// on a surface where nothing hovers to tell you what you are about to hit.
    public static let rowTouch: CGFloat = 52

    // MARK: - Typography
    //
    // Named, because every call site used to hardcode `.system(size:)` — which is how
    // 9.5, 10, 10.5, 11, 12, 13, 16 and 20 all ended up in one panel.
    //
    // That fix did not hold. There are 21 distinct sizes in the app at the time of
    // writing — 7.5, 8, 8.5, 9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 14, 15, 17, 18,
    // 20, 21, 22, 25, 26 — which is worse than the drift this scale replaced, and
    // `KeyHint` sets two adjacent labels at 10 and 10.5. The reason is that the scale
    // was semantic-only: a call site wanting a small chip had no rung to stand on, so
    // it invented one. The rungs below close that gap, and the semantic names sit on
    // top of them.

    public enum Typography {
        // The scale. Eight rungs, and nothing between them.
        public static let micro = Font.system(size: 10)
        public static let caption = Font.system(size: 11)
        public static let body = Font.system(size: 12)
        public static let title = Font.system(size: 13)
        public static let heading = Font.system(size: 15)
        public static let field = Font.system(size: 18)
        public static let display = Font.system(size: 21)
        public static let statement = Font.system(size: 25)

        // Roles, in terms of the scale.
        /// Matched characters. Emphasis by weight and tier, never by hue.
        public static let titleMatch = Font.system(size: 13, weight: .semibold)
        public static let subtitle = title
        public static let meta = caption
        public static let section = Font.system(size: 11, weight: .semibold)
        public static let key = Font.system(size: 11, weight: .medium)
    }

    // MARK: - Iconography
    //
    // A scale the app never had. Every `Image(systemName:)` picked its own number,
    // which is how 8, 8.5, 9, 9.5, 20, 22 and 26 got into the type inventory above —
    // they were never type sizes at all. Weight drifted the same way: the lock glyph
    // is drawn at .light, .regular, .medium and .bold in four different places.

    public enum Icon {
        public static let micro = Font.system(size: 9)
        public static let small = Font.system(size: 11)
        public static let regular = Font.system(size: 13)
        public static let large = Font.system(size: 15)
        /// Empty states and sheet headers, where the glyph is the illustration.
        public static let hero = Font.system(size: 26, weight: .light)

        /// Fixed slots, so a glyph's own width cannot shunt the text beside it. A
        /// paperclip and a text.alignleft are not the same width; a row of them
        /// should still start at the same x.
        public static let slotCompact: CGFloat = 16
        public static let slot: CGFloat = 20
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

    // State changes may animate; entrances still may not. The rule from 07d3a88 holds
    // exactly where it was aimed — nothing on the search path moves, because the
    // re-rank behind it completes in half a millisecond and animating that result
    // would spend the win. Hover and selection are not the search path: they answer a
    // pointer or an arrow key, and a hard cut there reads as a flicker.
    public static let hover = Animation.easeOut(duration: 0.09)
    public static let selectionChange = Animation.easeOut(duration: 0.12)
    public static let disclosure = Animation.easeOut(duration: 0.14)

    // MARK: - Elevation
    //
    // Shadows were four hand-picked black alphas (0.18, 0.22, 0.28) scattered across
    // the action menu, the panel scrim, the tag dropdown and the toast. A black shadow
    // over a light ground is one of the more visible light-mode bugs, so these carry
    // an appearance like everything else.

    public struct Shadow: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let y: CGFloat
    }

    /// Namespaced because `Theme.sheet` is already the sheet's *animation*. Two things
    /// about the same surface, and neither name wants to be the awkward one.
    public enum Elevation {
        /// A menu or dropdown lifted off the surface below it.
        public static let popover = Shadow(
            color: Color(platform: .dyn(light: .srgb(0, 0, 0, 0.16), dark: .srgb(0, 0, 0, 0.34))),
            radius: 14, y: 6)
        /// A sheet, which sits higher and casts further.
        public static let sheet = Shadow(
            color: Color(platform: .dyn(light: .srgb(0, 0, 0, 0.20), dark: .srgb(0, 0, 0, 0.42))),
            radius: 22, y: 10)
        /// A toast, which is small and should not look heavy.
        public static let toast = Shadow(
            color: Color(platform: .dyn(light: .srgb(0, 0, 0, 0.12), dark: .srgb(0, 0, 0, 0.28))),
            radius: 10, y: 4)
    }



    // MARK: - Brand
    //
    // The icon's own ground and violets, fixed rather than dynamic. These are for the
    // surfaces that are the identity rather than the work — onboarding, the mark, an
    // empty state that carries it. They do not follow the system appearance because
    // the mark is drawn on near-black and its bloom only reads there.
    //
    // Onboarding kept these privately as an `Ink` enum, which meant the app had two
    // colour systems that happened to agree. One is enough.

    public enum Brand {
        public static let page = Color(red: 0.055, green: 0.055, blue: 0.071)
        public static let rail = Color(red: 0.086, green: 0.082, blue: 0.106)
        public static let violet = Color(red: 0.64, green: 0.55, blue: 1.00)
        public static let violetBright = Color(red: 0.84, green: 0.80, blue: 1.00)
        public static let violetDeep = Color(red: 0.42, green: 0.30, blue: 0.92)
        public static let primary = Color.white.opacity(0.94)
        public static let secondary = Color.white.opacity(0.58)
        public static let faint = Color.white.opacity(0.40)
        public static let card = Color.white.opacity(0.05)
        public static let hairline = Color.white.opacity(0.10)
    }

    // MARK: - Type colours
    //
    // Kept. These say what kind of thing a row is, and they are always drawn as the
    // glyph itself — never as a fill. `.text` is the same violet as `accent` on
    // purpose: they never collide because they never take the same role, and a kind
    // glyph on the selection tint still measures 4.5:1. On a solid accent it would be
    // 1.00:1, which is why the selection fill is a tint and not a colour choice.

    public static func color(for kind: ItemKind) -> Color {
        switch kind {
        case .text: Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78), dark: .srgb(0.64, 0.55, 1.00)))
        case .richText: Color(platform: .dyn(light: .srgb(0.22, 0.36, 0.80), dark: .srgb(0.50, 0.66, 1.00)))
        case .image: Color(platform: .dyn(light: .srgb(0.05, 0.52, 0.52), dark: .srgb(0.33, 0.83, 0.80)))
        // Darker in light than it looks like it should be, for the same reason
        // `warning` is: amber on a near-white ground is always the one that fails. At
        // 0.76/0.44/0.07 it measured 3.43:1 on the chrome — over the 3:1 glyph bar by
        // a hair — and 2.78:1 once a selected row put the accent tint underneath it.
        case .document: Color(platform: .dyn(light: .srgb(0.66, 0.38, 0.04), dark: .srgb(1.00, 0.71, 0.32)))
        case .file: Color(platform: .dyn(light: .srgb(0.36, 0.40, 0.48), dark: .srgb(0.66, 0.71, 0.80)))
        }
    }

    /// Named folder colours, kept small on purpose.
    public static let folderColorNames = ["violet", "blue", "teal", "green", "amber", "red", "graphite"]

    public static func folderColor(_ name: String) -> Color {
        switch name {
        case "blue": Color(platform: .dyn(light: .srgb(0.15, 0.40, 0.85), dark: .srgb(0.45, 0.66, 1.00)))
        case "teal": Color(platform: .dyn(light: .srgb(0.05, 0.52, 0.52), dark: .srgb(0.33, 0.83, 0.80)))
        case "green": Color(platform: .dyn(light: .srgb(0.15, 0.52, 0.26), dark: .srgb(0.42, 0.84, 0.53)))
        case "amber": Color(platform: .dyn(light: .srgb(0.76, 0.47, 0.05), dark: .srgb(1.00, 0.73, 0.30)))
        case "red": Color(platform: .dyn(light: .srgb(0.75, 0.20, 0.22), dark: .srgb(1.00, 0.47, 0.45)))
        case "graphite": Color(platform: .dyn(light: .srgb(0.36, 0.40, 0.46), dark: .srgb(0.68, 0.72, 0.78)))
        case "violet": Color(platform: .dyn(light: .srgb(0.36, 0.25, 0.78), dark: .srgb(0.64, 0.55, 1.00)))
        default: Color(platform: .dyn(light: .srgb(0.36, 0.40, 0.46), dark: .srgb(0.68, 0.72, 0.78)))
        }
    }
}

// MARK: - Colour helpers

/// `NSColor` on macOS, `UIColor` on iOS.
///
/// Every token below is a pair of sRGB literals wrapped in `.dyn`, and the numbers
/// are the design system — `ContrastTests` asserts each text tier against its
/// background at WCAG AA, and the first monochrome palette here sat at 2.65:1 while
/// looking perfectly fine on screen. So the port keeps every literal exactly as it
/// was and changes only which framework resolves it.
#if canImport(AppKit)
public typealias PlatformColor = NSColor
#else
public typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        #else
        UIColor(red: r, green: g, blue: b, alpha: a)
        #endif
    }

    /// One colour, correct in both appearances — never a value defined only for dark.
    static func dyn(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
        #else
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }
}

extension Color {
    public init(platform: PlatformColor) {
        #if canImport(AppKit)
        self.init(nsColor: platform)
        #else
        self.init(uiColor: platform)
        #endif
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
