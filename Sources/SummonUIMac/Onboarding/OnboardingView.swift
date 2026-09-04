import AppKit
import SwiftUI
import SummonKit
import SummonUI
import SummonKitMac

/// First run. Three short steps: what this is, the shortcut, and the two optional
/// things worth offering before someone starts.
///
/// This is the one surface that breaks the monochrome rule in `DesignTokens`, and it
/// does so deliberately. That rule is about working chrome — a tinted selection bar
/// means nothing and so earns no colour. Onboarding is seen once, before any work has
/// started, and its job is not to get out of the way but to say what this is. So it
/// carries the app icon's own palette — `Theme.Brand`, the near-black ground and the
/// one violet — and is always dark, whatever the system is set to, for the same reason
/// the icon is: that is the ground the mark was drawn on, and its bloom only reads
/// there. A light onboarding would be a second design to maintain forever for a screen
/// seen once.
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
            Theme.Brand.page

            // A soft lift under the mark's side, faded out rather than ruled off. The
            // rail is a place, not a border.
            LinearGradient(colors: [Theme.Brand.rail, Theme.Brand.rail.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 540)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The bloom from the icon, centred on the mark and deliberately wider than
            // the rail it sits in.
            RadialGradient(colors: [Theme.Brand.violetDeep.opacity(0.50),
                                    Theme.Brand.violetDeep.opacity(0.15),
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
                    LinearGradient(colors: [Theme.Brand.violetBright, Theme.accent, Theme.Brand.violetDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 104, height: 104)
                .shadow(color: Theme.Brand.violet.opacity(0.55), radius: 22)

            Text("Summon")
                .font(Theme.Typography.field.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
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
                .font(Theme.Typography.statement.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
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
                        get: { MacSettings.shared.summonHotKey },
                        set: { MacSettings.shared.summonHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }

                settingRow("Save what’s selected", "Grabs your selection or Finder files.") {
                    HotKeyRecorder(combo: Binding(
                        get: { MacSettings.shared.quickSaveHotKey },
                        set: { MacSettings.shared.quickSaveHotKey = $0 }
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
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let Summon paste for you")
                            .font(Theme.Typography.title.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                        Text("Otherwise it copies, and you press ⌘V yourself.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if Inserter.hasAccessibility {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.accent)
                    } else {
                        Button("Allow…") { Inserter.requestAccessibility() }
                            .buttonStyle(.summonQuiet)
                    }
                }
            }

            card {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start with a few examples")
                            .font(Theme.Typography.title.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                        Text("Snippets, a document and an image. Delete anytime.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if seeded {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.accent)
                    } else if seeding {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { seedLibrary() }
                            .buttonStyle(.summonQuiet)
                    }
                }
            }
        }
    }

    // MARK: - Chrome

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title)
                .font(Theme.Typography.display.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(subtitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.secondaryText)
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
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.accent)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Space.s)
            .cardBackground(radius: Theme.Radius.large)
    }

    private func settingRow<Control: View>(_ title: String, _ detail: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        card {
            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.Typography.title.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                    Text(detail)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.secondaryText)
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
                    .fill(index == step ? Theme.accent : Theme.hairline)
                    .frame(width: index == step ? 18 : 6, height: 6)
                    .animation(Theme.panelIn, value: step)
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.summonQuiet)
            }
            Button(step == lastStep ? "Start using Summon" : "Continue") {
                if step == lastStep { finish() } else { step += 1 }
            }
            .buttonStyle(.summonPrimary)
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
