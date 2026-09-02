import AppKit
import SwiftUI
import SummonKit

/// The single source of Summon's visual identity.
///
/// The bones are system-native — materials, vibrancy, SF Symbols, system type — so
/// the app feels instantaneous and at home. The identity comes from a violet-and-amber
/// pairing, colour-coded type glyphs, one consistent spacing rhythm, and a single
/// signature spring. Every colour is defined for both appearances.
public enum Theme {

    // MARK: - Palette

    public static let accent = Color(nsColor: .dyn(light: .srgb(0.36, 0.25, 0.78), dark: .srgb(0.60, 0.50, 1.00)))
    public static let accentDeep = Color(nsColor: .dyn(light: .srgb(0.28, 0.18, 0.66), dark: .srgb(0.48, 0.38, 0.95)))
    public static let accentWash = Color(nsColor: .dyn(light: .srgb(0.36, 0.25, 0.78, 0.10), dark: .srgb(0.62, 0.52, 1.00, 0.20)))

    /// The "summoned" highlight. Used sparingly: the spark, the pin, the match.
    public static let spark = Color(nsColor: .dyn(light: .srgb(0.82, 0.53, 0.03), dark: .srgb(1.00, 0.74, 0.28)))
    public static let sparkWash = Color(nsColor: .dyn(light: .srgb(1.00, 0.74, 0.26, 0.18), dark: .srgb(1.00, 0.74, 0.26, 0.22)))

    public static let danger = Color(nsColor: .dyn(light: .srgb(0.78, 0.18, 0.18), dark: .srgb(1.00, 0.42, 0.40)))
    public static let success = Color(nsColor: .dyn(light: .srgb(0.10, 0.55, 0.30), dark: .srgb(0.36, 0.85, 0.55)))

    public static let primaryText = Color(nsColor: .labelColor)
    public static let secondaryText = Color(nsColor: .secondaryLabelColor)
    public static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    public static let hairline = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.09), dark: .srgb(1, 1, 1, 0.11)))
    public static let surface = Color(nsColor: .dyn(light: .srgb(1, 1, 1, 0.72), dark: .srgb(1, 1, 1, 0.055)))
    public static let surfaceRaised = Color(nsColor: .dyn(light: .srgb(1, 1, 1, 0.95), dark: .srgb(1, 1, 1, 0.09)))
    public static let rowHover = Color(nsColor: .dyn(light: .srgb(0, 0, 0, 0.045), dark: .srgb(1, 1, 1, 0.06)))

    // MARK: - Rhythm

    public enum Space {
        public static let xxs: CGFloat = 3
        public static let xs: CGFloat = 6
        public static let s: CGFloat = 10
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 36
    }

    public enum Radius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 10
        public static let large: CGFloat = 16
        public static let panel: CGFloat = 20
    }

    // MARK: - Motion

    /// The signature summon spring: quick, with just enough settle to feel physical.
    public static let summonSpring = Animation.spring(response: 0.30, dampingFraction: 0.80)
    public static let quick = Animation.spring(response: 0.20, dampingFraction: 0.90)
    public static let gentle = Animation.easeOut(duration: 0.16)
    /// Per-row delay for the results stagger.
    public static let stagger: Double = 0.012

    // MARK: - Type colours

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
        default: accent
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

    /// Applies the summon entrance, honouring Reduce Motion.
    func summonTransition(isVisible: Bool, reduceMotion: Bool) -> some View {
        scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.96))
            .opacity(isVisible ? 1 : 0)
            .animation(reduceMotion ? .linear(duration: 0.01) : Theme.summonSpring, value: isVisible)
    }
}
