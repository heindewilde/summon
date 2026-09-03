import AppKit
import SwiftUI
import SummonKit

/// First run. Four short steps: what this is, the shortcut, a chance to actually
/// press it, and something to press it on.
///
/// This is the one surface that breaks the monochrome rule in `DesignTokens`, and it
/// does so deliberately. That rule is about working chrome — a tinted selection bar
/// means nothing and so earns no colour. Onboarding is seen once, before any work has
/// started, and its job is not to get out of the way but to say what this is. So it
/// carries the app icon's own palette: the near-black ground, the one violet, the
/// bloom behind the mark. It is also always dark, whatever the system is set to, for
/// the same reason the icon is — that is the ground the mark was drawn on.
///
/// What is *not* here matters as much. Encryption setup used to live on step three as
/// a segmented picker, two secure fields, a Set button and a checkbox — a settings
/// form in the middle of a welcome, asking someone to protect a library that is still
/// empty. It is one line in Settings now.
public struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int
    @State private var seeding = false
    @State private var seeded = false
    /// Set when the panel first appears, so step three can acknowledge the press.
    @State private var hasSummoned = false
    /// Drives the mark stroking itself on, once, when the window opens.
    @State private var markProgress: CGFloat = 0

    private let lastStep = 3

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
            Rectangle()
                .fill(Ink.hairline)
                .frame(width: 1)
            column
        }
        .frame(width: 760, height: 420)
        .background(Ink.page)
        // Always dark: the palette below is fixed, and this makes the system controls
        // inside it — the hot key recorders, the progress spinner — agree.
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { markProgress = 1 }
        }
        .onChange(of: model.isPanelVisible) { _, visible in
            if visible { hasSummoned = true }
        }
    }

    // MARK: - Rail

    /// The identity, held on screen for the whole flow rather than shown once on step
    /// one and then abandoned.
    private var rail: some View {
        ZStack {
            Ink.rail

            // The bloom from the icon. Sized well past the mark so its falloff is what
            // shows, not its edge.
            RadialGradient(colors: [Ink.violetDeep.opacity(0.45), .clear],
                           center: .center, startRadius: 0, endRadius: 190)
                .frame(width: 380, height: 380)
                .offset(y: -26)

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
            .offset(y: -18)
        }
        .frame(width: 268)
        .clipped()
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
        case 2: tryIt
        default: library
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
                bullet("text.alignleft", "Replies and boilerplate, with fill-in fields.")
                bullet("photo.on.rectangle", "Images, PDFs and documents.")
                bullet("bolt.fill", "One shortcut, from anywhere.")
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

    /// The one screen that shows rather than tells. The shortcut is already registered
    /// by the time this window opens — `AppDelegate` does it at launch, long before
    /// onboarding — so the panel really does open over this window when they press it.
    private var tryIt: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Try it", "The panel opens over whatever you’re doing.")

            // The only screen with a single thing to do, so that thing is the biggest
            // thing on it rather than a chip in the corner.
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                keycap
                if hasSummoned {
                    Label("That’s the whole idea.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: Size.body))
                        .foregroundStyle(Ink.violet)
                } else {
                    Text("Press it now — this window will wait.")
                        .font(.system(size: Size.body))
                        .foregroundStyle(Ink.secondary)
                }
            }
            .padding(.vertical, Theme.Space.s)

            card {
                HStack(alignment: .top, spacing: Theme.Space.s) {
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
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Start with a few examples?",
                      "Snippets, a document and an image. Delete them whenever.")

            HStack(spacing: Theme.Space.s) {
                Button(seeded ? "Examples added" : "Add examples") { seedLibrary() }
                    .buttonStyle(QuietButton())
                    .disabled(seeding || seeded)
                if seeding { ProgressView().controlSize(.small) }
                Spacer()
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                bullet("square.dashed.inset.filled", "Write {{first_name}} and Summon asks for it as you insert.")
                bullet("number", "Filter as you type: #tag, /folder, img:, pdf:, txt:")
                bullet("pin", "Pinned items come first, before you type anything.")
            }
            .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: - Chrome

    private var keycap: some View {
        Text(model.settings.summonHotKey.displayString)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Ink.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                            .strokeBorder(Ink.hairline, lineWidth: 1)
                    )
            )
    }

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

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(Ink.violet)
                .frame(width: 18)
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

            // An escape hatch. There was none: the flow could only be finished by
            // walking every step, and step three now asks for a keypress that another
            // app may already have taken.
            if step < lastStep {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: Size.detail))
                    .foregroundStyle(Ink.faint)
            }

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
