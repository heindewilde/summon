import AppKit
import SwiftUI
import Testing
@testable import SummonUI
import SummonKit

/// Contrast is arithmetic, so it should be asserted rather than eyeballed.
///
/// The first monochrome palette put the panel row's body preview at 3.20:1 in dark
/// and 2.65:1 in light — both well under the 4.5:1 needed at 11–13pt — and looked
/// perfectly acceptable on screen. That is exactly why this is a test.
///
/// These assertions read `Theme` itself. The previous version lived in SummonKitTests,
/// which cannot import SummonUI, so it hand-copied every alpha as a raw number and
/// called the duplication deliberate — but a token could then be changed without
/// failing anything, which made the guard decorative at precisely the moment a palette
/// change needed one.
@MainActor
@Suite("Contrast")
struct ContrastTests {

    // MARK: - Measuring a token

    struct RGB { var r, g, b: Double }

    /// A token's real sRGB value in one appearance, opacity included.
    ///
    /// The colour is built *inside* the appearance block: `Theme`'s colours are dynamic
    /// providers, and resolving one outside the block would silently bake in whatever
    /// appearance the test process happened to be in.
    static func resolve(_ token: @autoclosure () -> Color, dark: Bool) -> (RGB, Double) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var rgb = RGB(r: 0, g: 0, b: 0)
        var alpha = 1.0
        appearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(token()).usingColorSpace(.sRGB)!
            rgb = RGB(r: resolved.redComponent * 255,
                      g: resolved.greenComponent * 255,
                      b: resolved.blueComponent * 255)
            alpha = resolved.alphaComponent
        }
        return (rgb, alpha)
    }

    // MARK: - WCAG

    static func linear(_ channel: Double) -> Double {
        let c = channel / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ colour: RGB) -> Double {
        0.2126 * linear(colour.r) + 0.7152 * linear(colour.g) + 0.0722 * linear(colour.b)
    }

    static func blend(_ foreground: RGB, alpha: Double, over background: RGB) -> RGB {
        RGB(r: foreground.r * alpha + background.r * (1 - alpha),
            g: foreground.g * alpha + background.g * (1 - alpha),
            b: foreground.b * alpha + background.b * (1 - alpha))
    }

    static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The vibrancy material under the chrome. The one value here that is not ours —
    /// it is AppKit's `hudWindow`, measured, because a material cannot be resolved.
    static func material(dark: Bool) -> RGB {
        dark ? RGB(r: 40, g: 40, b: 42) : RGB(r: 240, g: 240, b: 240)
    }

    /// What a token actually sits on: `Theme.chrome`, which is translucent, over that.
    static func ground(dark: Bool) -> RGB {
        let (chrome, alpha) = resolve(Theme.chrome, dark: dark)
        return blend(chrome, alpha: alpha, over: material(dark: dark))
    }

    /// A token drawn as ink on the ground, against its bar.
    static func check(_ token: @autoclosure () -> Color, _ name: String,
                      bar: Double, dark: Bool) {
        let base = ground(dark: dark)
        let (ink, alpha) = resolve(token(), dark: dark)
        let measured = ratio(blend(ink, alpha: alpha, over: base), base)
        #expect(measured >= bar,
                "\(name) is \(String(format: "%.2f", measured)):1 in \(dark ? "dark" : "light"), needs \(bar):1")
    }

    // MARK: - Text

    @Test("Text tiers meet their contrast bar", arguments: [true, false])
    func textTiers(dark: Bool) {
        Self.check(Theme.primaryText, "primaryText", bar: 4.5, dark: dark)
        Self.check(Theme.secondaryText, "secondaryText", bar: 4.5, dark: dark)
        Self.check(Theme.tertiaryText, "tertiaryText", bar: 4.5, dark: dark)
        // Decoration only: the ⌘-number badge. Held to the non-text bar.
        Self.check(Theme.faintText, "faintText", bar: 3.0, dark: dark)
    }

    @Test("The tiers stay in order, so hierarchy reads as hierarchy", arguments: [true, false])
    func tiersAreOrdered(dark: Bool) {
        let base = Self.ground(dark: dark)
        let measured = [Theme.primaryText, Theme.secondaryText,
                        Theme.tertiaryText, Theme.faintText].map { token -> Double in
            let (ink, alpha) = Self.resolve(token, dark: dark)
            return Self.ratio(Self.blend(ink, alpha: alpha, over: base), base)
        }
        #expect(measured == measured.sorted(by: >),
                "tiers out of order in \(dark ? "dark" : "light"): \(measured)")
    }

    // MARK: - Colour that carries meaning
    //
    // None of this was covered before: the tests only ever knew about the four text
    // tiers, so every colour that actually says something could drift freely.

    @Test("Status colours are readable as text", arguments: [true, false])
    func statusColours(dark: Bool) {
        Self.check(Theme.danger, "danger", bar: 4.5, dark: dark)
        Self.check(Theme.success, "success", bar: 4.5, dark: dark)
        Self.check(Theme.warning, "warning", bar: 4.5, dark: dark)
    }

    @Test("Kind glyphs clear the non-text bar", arguments: [true, false])
    func kindColours(dark: Bool) {
        for kind in ItemKind.allCases {
            Self.check(Theme.color(for: kind), "kind \(kind.rawValue)", bar: 3.0, dark: dark)
        }
    }

    @Test("Folder colours clear the non-text bar", arguments: [true, false])
    func folderColours(dark: Bool) {
        for name in Theme.folderColorNames {
            Self.check(Theme.folderColor(name), "folder \(name)", bar: 3.0, dark: dark)
        }
    }
}
