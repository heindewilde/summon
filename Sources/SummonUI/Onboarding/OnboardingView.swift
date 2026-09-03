import AppKit
import SwiftUI
import SummonKit

/// First run. Three short steps: what this is, the shortcut, and the two optional
/// things worth offering before someone starts.
///
/// This is the one surface that breaks the monochrome rule in `DesignTokens`, and it
/// does so deliberately. That rule is about working chrome — a tinted selection bar
/// means nothing and so earns no colour. Onboarding is seen once, before any work has
/// started, and its job is not to get out of the way but to say what this is. So it
/// carries the app icon's own palette: the near-black ground, the one violet, the
/// bloom behind the mark. It is also always dark, whatever the system is set to, for
/// the same reason the icon is — that is the ground the mark was drawn on.
///
/// What is *not* here matters as much. Encryption setup used to live mid-flow as a
/// segmented picker, two secure fields, a Set button and a checkbox — a settings form
/// in the middle of a welcome, asking someone to protect a library that is still
/// empty. It is one line in Settings now. There is no Skip either: at three steps,
/// two of which ask nothing, there is nothing left worth skipping past.
public struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int
    @State private var seeding = false
    @State private var seeded = false
    /// Drives the mark stroking itself on, once, when the window opens.
    @State private var markProgress: CGFloat = 0

    private let lastStep = 2

    /// `initialStep` jumps straight to a card, for the same reason `LockSheet` takes an
    /// initial kind: a still frame cannot click Continue three times.
    public init(model: AppModel, initialStep: Int = 0) {
        self.model = model
        _step = State(initialValue: initialStep)
    }

    /// The type scale. This had six sizes between 11 and 12.5pt doing four different
    /// jobs, which is why everything under a heading read as one undifferentiated grey.
    /// Five sizes, each with one job, and a real gap between them.
    private enum Size {
        static let statement: CGFloat = 25
        static let title: CGFloat = 21
        static let body: CGFloat = 13
        static let detail: CGFloat = 12
        static let wordmark: CGFloat = 17
    }

    public var body: some View {
        HStack(spacing: 0) {
            rail
            column
        }
        .frame(width: 760, height: 420)
        // As a background rather than a sibling in a ZStack: the bloom is deliberately
        // larger than the window, and as a sibling its frame drove the stack's height,
        // laying the steps out 700pt tall and pushing the footer past the clip.
        .background(atmosphere)
        .clipped()
        // Always dark: the palette below is fixed, and this makes the system controls
        // inside it — the hot key recorders, the progress spinner — agree.
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { markProgress = 1 }
        }
    }

    // MARK: - Ground

    /// One continuous ground for the whole window. The mark's glow lives here rather
    /// than inside the rail, so it carries across the middle instead of stopping dead
    /// at a divider — the light comes from an object on the page, and light does not
    /// respect a column edge.
    private var atmosphere: some View {
        ZStack {
            Ink.page

            // A soft lift under the mark's side, faded out rather than ruled off. The
            // rail is a place, not a border.
            LinearGradient(colors: [Ink.rail, Ink.rail.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 540)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The bloom from the icon, centred on the mark and deliberately wider than
            // the rail it sits in.
            RadialGradient(colors: [Ink.violetDeep.opacity(0.50),
                                    Ink.violetDeep.opacity(0.15),
                                    .clear],
                           center: .center, startRadius: 0, endRadius: 350)
                .frame(width: 700, height: 700)
                .offset(x: -Self.railWidth / 2 - 112, y: -26)
        }
    }

    // MARK: - Rail

    /// The identity, held on screen for the whole flow rather than shown once on step
    /// one and then abandoned. No ground of its own — that is in `atmosphere`.
    private static let railWidth: CGFloat = 268

    private var rail: some View {
        VStack(spacing: Theme.Space.m) {
            SummonMarkShape(progress: markProgress)
                .fill(
                    LinearGradient(colors: [Ink.violetBright, Ink.violet, Ink.violetDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 104, height: 104)
                .shadow(color: Ink.violet.opacity(0.55), radius: 22)

            Text("Summon")
                .font(.system(size: Size.wordmark, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .opacity(markProgress)
        }
        .frame(width: Self.railWidth)
        .offset(y: -18)
    }

    // MARK: - Column

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Centred against the rail's mark rather than pinned to the top: the steps
            // are short, and top-aligning them left every one of them with a dead band
            // along the bottom while the mark sat at the middle of the panel beside it.
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.l)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: shortcuts
        default: finishing
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("One place for the things you reuse.")
                .font(.system(size: Size.statement, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                bullet("text.alignleft", "Save what you retype — a standard reply, your VAT number, an address.")
                bullet("paperclip", "And the files you dig out every week: the portfolio PDF, the headshot.")
                bullet("bolt.fill", "One keystroke drops any of them into the app you’re already in.")
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Choose your shortcut", "Press it from any app.")

            VStack(spacing: Theme.Space.s) {
                settingRow("Summon panel", "Opens the search panel.") {
                    HotKeyRecorder(combo: Binding(
                        get: { model.settings.summonHotKey },
                        set: { model.settings.summonHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }

                settingRow("Save what’s selected", "Grabs your selection or Finder files.") {
                    HotKeyRecorder(combo: Binding(
                        get: { model.settings.quickSaveHotKey },
                        set: { model.settings.quickSaveHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }
            }
        }
    }

    /// The last screen: the one permission worth offering, and the one shortcut into a
    /// library that is otherwise empty. Both are offers, so both are cards of the same
    /// shape — Allow/Allowed and Add/Added read as the same kind of choice.
    private var finishing: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Before you start", "Both optional — Summon works without either.")

            card {
                // Centred rather than top-aligned: the status sits opposite a two-line
                // block, and aligning it to the top left it riding above the title it
                // belongs to.
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(Ink.primary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let Summon paste for you")
                            .font(.system(size: Size.body, weight: .medium))
                            .foregroundStyle(Ink.primary)
                        Text("Otherwise it copies, and you press ⌘V yourself.")
                            .font(.system(size: Size.detail))
                            .foregroundStyle(Ink.secondary)
                    }
                    Spacer()
                    if Inserter.hasAccessibility {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: Size.detail))
                            .foregroundStyle(Ink.violet)
                    } else {
                        Button("Allow…") { Inserter.requestAccessibility() }
                            .buttonStyle(QuietButton())
                    }
                }
            }

            card {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(Ink.primary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start with a few examples")
                            .font(.system(size: Size.body, weight: .medium))
                            .foregroundStyle(Ink.primary)
                        Text("Snippets, a document and an image. Delete anytime.")
                            .font(.system(size: Size.detail))
                            .foregroundStyle(Ink.secondary)
                    }
                    Spacer()
                    if seeded {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.system(size: Size.detail))
                            .foregroundStyle(Ink.violet)
                    } else if seeding {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { seedLibrary() }
                            .buttonStyle(QuietButton())
                    }
                }
            }
        }
    }

    // MARK: - Chrome

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title)
                .font(.system(size: Size.title, weight: .semibold))
                .foregroundStyle(Ink.primary)
            Text(subtitle)
                .font(.system(size: Size.body))
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Aligned on the first text baseline, not the top of the row. A symbol's drawn
    /// box is taller than the letters beside it, so top-aligning the two leaves the
    /// glyph visibly riding above the line it belongs to — and worse once the text
    /// wraps. Giving the image the body font makes it a participant in that baseline.
    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: Size.body))
                .foregroundStyle(Ink.violet)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(.system(size: Size.body))
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Space.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Ink.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                            .strokeBorder(Ink.hairline, lineWidth: 1)
                    )
            )
    }

    private func settingRow<Control: View>(_ title: String, _ detail: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        card {
            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: Size.body, weight: .medium))
                        .foregroundStyle(Ink.primary)
                    Text(detail)
                        .font(.system(size: Size.detail))
                        .foregroundStyle(Ink.secondary)
                }
                Spacer()
                control()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(0...lastStep, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Ink.violet : Ink.hairline)
                    .frame(width: index == step ? 18 : 6, height: 6)
                    .animation(Theme.panelIn, value: step)
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(QuietButton())
            }
            Button(step == lastStep ? "Start using Summon" : "Continue") {
                if step == lastStep { finish() } else { step += 1 }
            }
            .buttonStyle(PrimaryButton())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, Theme.Space.m)
    }

    // MARK: - Actions

    private func seedLibrary() {
        seeding = true
        Task {
            await model.seedStarterLibraryIfEmpty()
            seeding = false
            seeded = true
        }
    }

    private func finish() {
        model.settings.hasCompletedOnboarding = true
        model.reregisterHotKeys()
        dismiss()
    }
}

// MARK: - Palette

/// Onboarding's own palette, fixed rather than dynamic. These are the app icon's
/// values: the ground it is drawn on, and `Colors.folderColor("violet")` dark, which
/// is the app's own accent. See the note on `OnboardingView` for why this surface
/// does not use `Theme`.
private enum Ink {
    static let page = Color(red: 0.055, green: 0.055, blue: 0.071)
    static let rail = Color(red: 0.086, green: 0.082, blue: 0.106)
    static let violet = Color(red: 0.64, green: 0.55, blue: 1.00)
    static let violetBright = Color(red: 0.84, green: 0.80, blue: 1.00)
    static let violetDeep = Color(red: 0.42, green: 0.30, blue: 0.92)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.40)
    static let card = Color.white.opacity(0.05)
    static let hairline = Color.white.opacity(0.10)
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Ink.page)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Ink.violet)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Ink.primary : Ink.faint)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Ink.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .strokeBorder(Ink.hairline, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
