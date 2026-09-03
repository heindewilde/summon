import AppKit
import SwiftUI
import SummonKit

/// Every PIN question, in one sheet.
///
/// There used to be four surfaces: a setup sheet, three cramped fields in Settings, a
/// confirmation alert, and — worst — the summon panel flying in over the library to
/// ask for a PIN you only wanted in order to tick one checkbox. They disagreed about
/// wording, about whether return was needed, and about where they appeared. This is
/// one sheet with one set of steps, shown on whichever window you are already using.
public struct PINSheet: View {
    @Bindable var model: AppModel

    public enum Purpose: Equatable, Identifiable {
        /// No PIN exists yet: choose one, then confirm it.
        case create
        /// Replace an existing one: prove the old, choose the new, confirm it.
        case change
        /// Open the vault so something can happen. `reason` finishes the sentence
        /// "Enter your PIN…", so it says what you actually asked for rather than
        /// announcing that everything is about to be unlocked.
        case unlock(reason: String)
        /// Remove protection: prove the PIN if locked, then confirm what it means.
        case turnOff

        public var id: String {
            switch self {
            case .create: "create"
            case .change: "change"
            case .unlock(let reason): "unlock:\(reason)"
            case .turnOff: "turnOff"
            }
        }
    }

    let purpose: Purpose
    let dismiss: () -> Void

    @State private var current = ""
    @State private var first = ""
    @State private var confirmation = ""
    @State private var step: Step
    @State private var error: String?
    @State private var shake = 0

    private enum Step { case current, choose, confirm, confirmRemoval }

    public init(model: AppModel, purpose: Purpose = .create,
                dismiss: @escaping () -> Void = {}) {
        self.model = model
        self.purpose = purpose
        self.dismiss = dismiss
        // Computed here rather than in `body`: a locked vault needs the PIN first,
        // an open one goes straight to the question being asked.
        let needsPIN = !model.vault.isUnlocked
        let start: Step
        switch purpose {
        case .create: start = .choose
        case .change, .unlock: start = .current
        case .turnOff: start = needsPIN ? .current : .confirmRemoval
        }
        _step = State(initialValue: start)
    }

    public var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: step == .confirmRemoval ? "lock.open" : "lock")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(step == .confirmRemoval ? Theme.danger : Theme.secondaryText)
                .padding(.top, Theme.Space.s)

            VStack(spacing: Theme.Space.xxs) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(subtitle)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step != .confirmRemoval {
                // Rebuilt per step — a fresh field, so the caret starts at the first
                // box and the boxes animate in rather than appearing already full.
                PINField(digits: binding(for: step), isError: error != nil, onComplete: advance)
                    .id(step)
                    .modifier(Shake(animatableData: CGFloat(shake)))
            }

            if steps.count > 1 { stepDots }

            if let error {
                Text(error)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let footnote {
                Text(footnote)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // macOS order: going back is on the left, deciding is on the right.
            HStack {
                if step != steps.first && step != .confirmRemoval {
                    Button("Back") { back() }
                }
                Spacer()
                Button("Cancel", role: .cancel) { cancel() }
                    .keyboardShortcut(.cancelAction)
                if step == .confirmRemoval {
                    Button("Turn Off PIN", role: .destructive) {
                        model.removePINProtection()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, Theme.Space.xs)
        }
        .padding(Theme.Space.l)
        .frame(width: 360)
    }

    // MARK: - Steps

    private var steps: [Step] {
        switch purpose {
        case .create: [.choose, .confirm]
        case .change: [.current, .choose, .confirm]
        case .unlock: [.current]
        case .turnOff: model.vault.isUnlocked ? [.confirmRemoval] : [.current, .confirmRemoval]
        }
    }

    private var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    private var title: String {
        switch step {
        case .current:
            if case .unlock = purpose { return "Enter your PIN" }
            return purpose == .change ? "Enter your current PIN" : "Enter your PIN"
        case .choose:
            return purpose == .change ? "Choose a new PIN" : "Choose a PIN"
        case .confirm:
            return "Enter it again"
        case .confirmRemoval:
            return "Turn off the PIN?"
        }
    }

    private var subtitle: String {
        switch step {
        case .current:
            if case .unlock(let reason) = purpose { return reason }
            if purpose == .turnOff { return "Turning protection off means decrypting what it protects." }
            return "So nobody who wanders past an unlocked Mac can change it."
        case .choose:
            return "Anything you mark sensitive is encrypted with a key only this PIN opens."
        case .confirm:
            return "So a slip of the finger cannot lock you out of your own things."
        case .confirmRemoval:
            return model.encryptedContentSummary
        }
    }

    private var footnote: String? {
        switch step {
        case .current: nil
        case .choose, .confirm:
            purpose == .change
                ? "Four digits. Everything sensitive is re-keyed to the new PIN."
                : "Four digits. There is no way to recover it, and no account to reset it from."
        case .confirmRemoval: "Nothing is deleted. You can set a new PIN at any time."
        }
    }

    private func binding(for step: Step) -> Binding<String> {
        switch step {
        case .current: $current
        case .choose: $first
        case .confirm, .confirmRemoval: $confirmation
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                Circle()
                    .fill(index == stepNumber - 1 ? Theme.primaryText : Theme.hairline)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Step \(stepNumber) of \(steps.count)")
    }

    // MARK: - Advancing

    private func advance() {
        error = nil
        switch step {
        case .current:
            // The PIN opens the vault here rather than being checked and discarded:
            // every purpose that asks for it needs the key next — to re-wrap it, to
            // decrypt with it, or to do the thing that was interrupted.
            guard model.unlockInPlace(pin: current) else {
                error = model.pinError
                wrongEntry { current = "" }
                return
            }
            switch purpose {
            case .unlock: dismiss()
            case .change: settle { step = .choose }
            case .turnOff: settle { step = .confirmRemoval }
            case .create: break
            }

        case .choose:
            guard PINPolicy.isValid(first) else {
                error = VaultError.pinNotFourDigits.errorDescription
                return
            }
            settle { step = .confirm }

        case .confirm:
            guard confirmation == first else {
                error = "Those didn’t match. Start again."
                wrongEntry {
                    first = ""
                    confirmation = ""
                    step = .choose
                }
                return
            }
            switch purpose {
            case .create: model.completePINSetup(pin: first) { error = $0 }
            case .change: model.changePIN(current: current, new: first) { error = $0 }
            case .unlock, .turnOff: break
            }
            if error == nil { dismiss() }

        case .confirmRemoval:
            break
        }
    }

    /// A beat before moving on, so the fourth box is seen to fill.
    private func settle(_ move: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            move()
        }
    }

    /// Shakes, then clears — after a beat, so the reason is read before the boxes
    /// empty themselves.
    private func wrongEntry(_ reset: @escaping () -> Void) {
        withAnimation(.default) { shake += 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            reset()
        }
    }

    private func back() {
        error = nil
        switch step {
        case .current, .confirmRemoval: break
        case .choose:
            first = ""
            if purpose == .change { step = .current; current = "" }
        case .confirm:
            confirmation = ""
            step = .choose
        }
    }

    private func cancel() {
        model.cancelPINSheet()
        dismiss()
    }
}

/// A short horizontal shake, for "that was wrong, try again".
///
/// Movement rather than only a colour change: an error message under a field is easy
/// to miss when your eyes are on the boxes.
private struct Shake: AnimatableModifier {
    var animatableData: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: sin(animatableData * .pi * 6) * 7)
    }
}
