import AppKit
import SwiftUI
import SummonKit

/// First run. Four short steps that set up the two things that genuinely need
/// explaining — a global shortcut and an Accessibility grant — and then get out.
public struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var pin = ""
    @State private var pinConfirm = ""
    @State private var pinError: String?
    @State private var enableTouchID = true
    @State private var seeding = false
    @State private var seeded = false

    private let lastStep = 3

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.xl)

            footer
        }
        .frame(width: 620, height: 470)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.10), .clear],
                           startPoint: .top, endPoint: .center)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: shortcuts
        case 2: privacy
        default: library
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: Theme.Space.m) {
            sparkMark
            Text("Summon")
                .font(.system(size: 30, weight: .semibold))
            Text("One place for the things you reuse.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                bullet("text.alignleft", "Canned replies, form details, and boilerplate — with fill-in fields so they arrive finished.")
                bullet("photo.on.rectangle", "Images, PDFs and documents you show clients, kept together with the words.")
                bullet("bolt.fill", "One shortcut, a few characters, and it lands where your cursor already is.")
            }
            .padding(.top, Theme.Space.s)
            .frame(maxWidth: 440, alignment: .leading)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Choose your shortcut",
                      "This is the one thing worth memorising. Press it from any app to summon your library.")

            VStack(spacing: Theme.Space.s) {
                settingRow("Summon panel", "Opens the search panel from anywhere.") {
                    HotKeyRecorder(combo: Binding(
                        get: { model.settings.summonHotKey },
                        set: { model.settings.summonHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }

                settingRow("Save what’s selected", "Grabs the current selection or Finder files straight into Summon.") {
                    HotKeyRecorder(combo: Binding(
                        get: { model.settings.quickSaveHotKey },
                        set: { model.settings.quickSaveHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }
            }

            Label("Global shortcuts need no special permission — Summon registers them with the system directly.",
                  systemImage: "checkmark.shield")
                .font(.system(size: 11))
                .foregroundStyle(Theme.success)
                .labelStyle(.titleAndIcon)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Pasting, and privacy",
                      "Two optional things. Summon works completely without either.")

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let Summon paste for you")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("macOS calls this Accessibility. It’s used for exactly one thing: pressing ⌘V in the app you were in. Without it, Summon copies and you paste — one extra keystroke.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if Inserter.hasAccessibility {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.success)
                    } else {
                        Button("Allow…") { Inserter.requestAccessibility() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(Theme.Space.s)
                .cardBackground()

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(Theme.spark)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set a PIN for sensitive items")
                                .font(.system(size: 12.5, weight: .medium))
                            Text("Encrypts anything you mark sensitive with AES-GCM on this Mac. Titles stay visible so you can still find them; contents don’t open without the PIN.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if model.vault.isConfigured {
                        Label("PIN set", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.success)
                    } else {
                        HStack(spacing: Theme.Space.xs) {
                            SecureField("PIN", text: $pin)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            SecureField("Confirm", text: $pinConfirm)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Button("Set") { setPIN() }
                                .buttonStyle(.bordered)
                                .disabled(pin.count < 4 || pin != pinConfirm)
                            if Vault.biometricsAvailable {
                                Toggle("Touch ID", isOn: $enableTouchID)
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 11))
                            }
                        }
                        if let pinError {
                            Text(pinError)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(Theme.Space.s)
                .cardBackground()
            }

            Label("Everything stays on this Mac. Summon has no accounts, no sync, and makes no network requests.",
                  systemImage: "wifi.slash")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .labelStyle(.titleAndIcon)
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Start with a few examples?",
                      "A small set of realistic snippets, a document and an image, so you can see how it feels. Delete them whenever.")

            HStack(spacing: Theme.Space.s) {
                Button {
                    seedLibrary()
                } label: {
                    Label(seeded ? "Examples added" : "Add examples",
                          systemImage: seeded ? "checkmark.circle.fill" : "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(seeding || seeded)

                if seeding { ProgressView().controlSize(.small) }
                Spacer()
            }

            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Three things worth knowing")
                    .font(.system(size: 12.5, weight: .semibold))
                bullet("square.dashed.inset.filled", "Write {{first_name}} in a snippet and Summon asks for it as you insert.")
                bullet("number", "Filter as you type: #tag, /folder, img:, pdf:, txt:")
                bullet("pin", "Pinned items always come first, before you type anything.")
            }
        }
    }

    // MARK: - Chrome

    private var sparkMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 84, height: 84)
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
        }
        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 6)
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title).font(.system(size: 21, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingRow<Control: View>(_ title: String, _ detail: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            control()
        }
        .padding(Theme.Space.s)
        .cardBackground()
    }

    private var footer: some View {
        HStack {
            ForEach(0...lastStep, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Theme.accent : Theme.hairline)
                    .frame(width: index == step ? 18 : 6, height: 6)
                    .animation(Theme.quick, value: step)
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Button(step == lastStep ? "Start using Summon" : "Continue") {
                if step == lastStep { finish() } else { step += 1 }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.m)
        .background(.thinMaterial)
    }

    // MARK: - Actions

    private func setPIN() {
        do {
            try model.vault.setUpPIN(pin)
            if enableTouchID, Vault.biometricsAvailable {
                try? model.vault.enableBiometricUnlock()
            }
            pinError = nil
            pin = ""; pinConfirm = ""
        } catch {
            pinError = (error as? VaultError)?.errorDescription ?? error.localizedDescription
        }
    }

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
