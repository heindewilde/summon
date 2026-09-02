import Foundation
import Testing

/// Contrast is arithmetic, so it should be asserted rather than eyeballed.
///
/// The first monochrome palette put the panel row's body preview at 3.20:1 in dark
/// and 2.65:1 in light — both well under the 4.5:1 needed at 11–13pt — and looked
/// perfectly acceptable on screen. That is exactly why this is a test.
///
/// Values are duplicated from `Theme` because SummonKit cannot import SummonUI. The
/// duplication is the point: if someone changes a token without changing these, the
/// test fails and asks why.
@Suite("Contrast")
struct ContrastTests {

    struct RGB { var r, g, b: Double }

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

    static let white = RGB(r: 255, g: 255, b: 255)
    static let black = RGB(r: 0, g: 0, b: 0)
    /// Theme.chrome at 0.72 over the hudWindow material.
    static let darkGround = blend(RGB(r: 28, g: 28, b: 30), alpha: 0.72,
                                  over: RGB(r: 40, g: 40, b: 42))
    static let lightGround = blend(RGB(r: 247, g: 247, b: 247), alpha: 0.72,
                                   over: RGB(r: 240, g: 240, b: 240))

    /// name, dark alpha, light alpha, required ratio
    static let tiers: [(String, Double, Double, Double)] = [
        ("primaryText", 0.95, 0.88, 4.5),
        ("secondaryText", 0.66, 0.64, 4.5),
        ("tertiaryText", 0.50, 0.58, 4.5),
        // Decoration only: the ⌘-number badge. Held to the non-text bar.
        ("faintText", 0.36, 0.45, 3.0),
    ]

    @Test("Every text tier meets its contrast bar in dark", arguments: tiers)
    func darkAppearance(_ tier: (String, Double, Double, Double)) {
        let (name, alpha, _, required) = tier
        let measured = Self.ratio(Self.blend(Self.white, alpha: alpha, over: Self.darkGround),
                                  Self.darkGround)
        #expect(measured >= required, "\(name) is \(measured):1, needs \(required):1")
    }

    @Test("Every text tier meets its contrast bar in light", arguments: tiers)
    func lightAppearance(_ tier: (String, Double, Double, Double)) {
        let (name, _, alpha, required) = tier
        let measured = Self.ratio(Self.blend(Self.black, alpha: alpha, over: Self.lightGround),
                                  Self.lightGround)
        #expect(measured >= required, "\(name) is \(measured):1, needs \(required):1")
    }

    @Test("The tiers stay in order, so hierarchy reads as hierarchy")
    func tiersAreOrdered() {
        func contrast(_ alpha: Double, dark: Bool) -> Double {
            dark ? Self.ratio(Self.blend(Self.white, alpha: alpha, over: Self.darkGround), Self.darkGround)
                 : Self.ratio(Self.blend(Self.black, alpha: alpha, over: Self.lightGround), Self.lightGround)
        }
        for dark in [true, false] {
            let values = Self.tiers.map { contrast(dark ? $0.1 : $0.2, dark: dark) }
            #expect(values == values.sorted(by: >), "tiers out of order in \(dark ? "dark" : "light")")
        }
    }
}
