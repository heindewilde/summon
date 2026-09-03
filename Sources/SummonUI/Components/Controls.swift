import SwiftUI

// The vocabulary the surfaces are built from.
//
// Each thing here existed already, several times over, written out by hand at every
// call site. The card shape was reimplemented ten times against one shared modifier
// used once; the "selected or hovering" fill nine times; the uppercased section header
// five times, one of which had already drifted off its own token. Duplication that
// wide is not a tidiness problem — it is why a change to the design system did not
// arrive everywhere, and why two surfaces could disagree about what selection looks
// like without anyone noticing.

// MARK: - Row state

/// What a row is currently saying about itself.
///
/// An enum rather than a pair of booleans, because the states are not independent and
/// the boolean version let a caller pass hover in as selection — which `MenuBarRow`
/// did, invisibly, right up until selection started meaning something.
public enum RowState: Sendable {
    case idle
    /// The pointer is here. Neutral: hover follows the mouse, and an accent that
    /// chases the cursor across a list strobes.
    case hover
    /// Chosen, and the keyboard acts on it.
    case selected
    /// Chosen, but the keyboard is in another pane. The macOS convention, and in a
    /// three-pane window the only way to say which column the arrow keys belong to.
    case selectedInactive
    /// Where you are in the navigation, which is not the same as what has focus.
    case navActive
    /// A drop lands inside this row.
    case dropTarget

    var fill: Color {
        switch self {
        case .idle, .dropTarget: .clear
        case .hover: Theme.rowHover
        case .selected: Theme.selection
        case .selectedInactive: Theme.selectionInactive
        case .navActive: Theme.navActive
        }
    }
}

public extension View {
    /// The background every selectable row shares.
    ///
    /// A selected row is a pane of glass laid on the surface, and a pane of glass is
    /// three things: a fill that is lighter where the light hits it, a bright specular
    /// line along its top edge, and a coloured glow it casts on what is underneath.
    /// A flat translucent fill has none of those, which is why the first version of
    /// this looked like a tinted rectangle.
    func rowSurface(_ state: RowState, radius: CGFloat = Theme.Radius.small) -> some View {
        let lit = state == .selected || state == .navActive
        return background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(colors: lit ? [state.fill, state.fill.opacity(0.45)]
                                               : [state.fill, state.fill],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: lit ? Theme.accent.opacity(0.45) : .clear, radius: 10, y: 2)
        }
        .overlay {
            if lit {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.selectionEdge, lineWidth: 1)
            }
        }
        .overlay(alignment: .top) {
            // The specular line. One pixel, and it is most of the effect.
            if lit {
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Theme.glassSheen, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                    .padding(.horizontal, radius)
            }
        }
        .overlay {
            // A ring, not a fill: a drop target drawn with the selection fill says
            // "this row is selected" instead — one pixel, two meanings.
            if state == .dropTarget {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.dropTarget, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .leading) {
            // "Where you are" needs to differ from "what the keys act on" by more than
            // four per cent of alpha. Side by side in the gallery the two fills were
            // indistinguishable, which is a distinction not worth a token — so this one
            // is structural. A rail reads instantly and survives at any tint.
            if state == .navActive {
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2.5, height: 16)
                    .padding(.leading, 2)
            }
        }
        .animation(Theme.hover, value: state)
    }

    /// A shadow from the elevation scale.
    func elevation(_ shadow: Theme.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }

    /// Makes a thing emit light rather than merely be coloured. The icon's mark is lit
    /// this way and it is the whole difference between a violet glyph and a glowing one.
    func glow(_ colour: Color, radius: CGFloat = 8, strength: Double = 0.55) -> some View {
        shadow(color: colour.opacity(strength), radius: radius)
    }
}

// MARK: - Bloom

/// The icon's light, as a property of the ground.
///
/// Two pools rather than one even wash: a surface lit from a single soft source reads
/// as a material with depth, and an evenly tinted one reads as a coloured rectangle.
/// Sized off the surface's own diagonal so the falloff is what shows, never the edge
/// of the gradient.
public struct Bloom: View {
    public var intensity: Double
    public init(intensity: Double = 1) { self.intensity = intensity }

    public var body: some View {
        GeometryReader { geo in
            let d = max(geo.size.width, geo.size.height)
            ZStack {
                // Tight and strong rather than wide and faint. A wash across a whole
                // surface reads as "this rectangle is slightly purple"; a pool with a
                // steep falloff reads as a light with something behind it.
                RadialGradient(colors: [Theme.bloom.opacity(intensity),
                                        Theme.bloom.opacity(intensity * 0.28), .clear],
                               center: .init(x: 0.08, y: -0.04),
                               startRadius: 0, endRadius: d * 0.55)
                RadialGradient(colors: [Theme.bloom.opacity(intensity * 0.7),
                                        Theme.bloom.opacity(intensity * 0.16), .clear],
                               center: .init(x: 1.02, y: 1.06),
                               startRadius: 0, endRadius: d * 0.45)
            }
        }
        .allowsHitTesting(false)
    }
}

public extension View {
    /// Lays the bloom over a surface's own ground, under its content.
    func bloomed(_ intensity: Double = 1) -> some View {
        background(Bloom(intensity: intensity))
    }
}

// MARK: - Rule

/// A hairline. `Divider()` paints the system separator, which is a different grey from
/// this app's hairline — so most of the codebase wrote `Divider().overlay(Theme.hairline)`
/// and thirteen places forgot, leaving two rule colours in one window.
///
/// Built *on* `Divider` rather than as a `Rectangle` of its own. The first version was a
/// fixed 1pt-high rectangle, which silently turned the vertical rule between the fill
/// pane and its preview into a horizontal one and let the preview column collapse.
/// `Divider` takes its axis from the stack it is in, and thirty call sites already
/// depend on that.
public struct Rule: View {
    public init() {}

    public var body: some View {
        Divider().overlay(Theme.hairline)
    }
}

// MARK: - Section header

/// The uppercased label above a group of rows.
public struct SectionHeader: View {
    public let title: String
    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title.uppercased())
            .font(Theme.Typography.section)
            .foregroundStyle(Theme.tertiaryText)
            .tracking(0.5)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Status

/// "This is done" / "this needs you" / "this will destroy something", as one shape.
public struct StatusBadge: View {
    public enum Tone: Sendable { case success, warning, danger, accent }

    public let tone: Tone
    public let label: String
    public init(_ label: String, tone: Tone = .success) {
        self.label = label
        self.tone = tone
    }

    private var colour: Color {
        switch tone {
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.danger
        case .accent: Theme.accent
        }
    }

    private var symbol: String {
        switch tone {
        case .success, .accent: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }

    public var body: some View {
        Label(label, systemImage: symbol)
            .font(Theme.Typography.caption)
            .foregroundStyle(colour)
    }
}

// MARK: - Key cap

/// One key, drawn as a key. Extracted from `KeyHint` so the menu bar's header — which
/// had hand-copied the same rounded rect and radius — can stop keeping its own.
public struct KeyCap: View {
    public let keys: String
    public init(_ keys: String) { self.keys = keys }

    public var body: some View {
        Text(keys)
            .font(Theme.Typography.micro.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Theme.hairline, in: .rect(cornerRadius: Theme.Radius.small - 1))
    }
}

// MARK: - Buttons

/// The app's buttons. `.bordered` and `.borderedProminent` are AppKit's capsules with
/// AppKit's hover chrome, and they sat inside custom panel surfaces looking borrowed.
public struct SummonButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, quiet, destructive }

    @Environment(\.isEnabled) private var isEnabled
    public var kind: Kind
    public init(_ kind: Kind = .quiet) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.title.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .primary ? Theme.Space.l : Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(background)
                    .overlay {
                        if kind != .primary {
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        }
                    }
            }
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.5))
            .animation(Theme.hover, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        // The accent inverts between appearances, so what reads on it inverts too.
        case .primary: Theme.onAccent
        case .quiet: Theme.primaryText
        case .destructive: Theme.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.accent
        case .quiet, .destructive: Theme.surface
        }
    }
}

public extension ButtonStyle where Self == SummonButtonStyle {
    static var summonPrimary: SummonButtonStyle { SummonButtonStyle(.primary) }
    static var summonQuiet: SummonButtonStyle { SummonButtonStyle(.quiet) }
    static var summonDestructive: SummonButtonStyle { SummonButtonStyle(.destructive) }
}

// MARK: - Fields

public extension View {
    /// A text field's well. A `ViewModifier` rather than a `TextFieldStyle` because the
    /// protocol's only real entry point is underscored; the call site pairs this with
    /// `.textFieldStyle(.plain)`, exactly as the three hand-rolled wells already did.
    func summonField(focused: Bool = false, radius: CGFloat = Theme.Radius.small) -> some View {
        padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(focused ? Theme.focusRing : Theme.hairline,
                                          lineWidth: focused ? 2 : 1)
                    }
            }
            .animation(Theme.hover, value: focused)
    }
}
