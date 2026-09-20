#if !canImport(AppKit)
import SummonKit
import SwiftUI

/// Unlocking, on a phone.
///
/// The Mac unlocks inside the summon panel, which is where a Mac asks for the PIN
/// because that is where you are when you need it. A phone has no panel, so the same
/// question gets a screen: Face ID if it is set up, the PIN underneath it, and the
/// state of the vault said plainly rather than implied by which controls are greyed.
struct VaultSheet: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void

    @State private var secret = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.xl) {
                Spacer(minLength: 0)

                Image(systemName: model.vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Space.s) {
                    Text(model.vault.isUnlocked ? "Sensitive items are unlocked" : "Sensitive items are locked")
                        .font(Theme.Typography.statement)
                    Text(model.vault.isUnlocked
                         ? "They lock themselves again when you leave Summon."
                         : "Titles stay searchable. Contents don't.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                if !model.vault.isUnlocked {
                    if model.vault.secretKind == .pin {
                        PINField(digits: $secret, isError: error != nil) { Task { await unlock() } }
                    } else {
                        SecureField("Passphrase", text: $secret)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.go)
                            .onSubmit { Task { await unlock() } }
                            .frame(maxWidth: 320)
                    }

                    if let error {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.danger)
                    }

                    if model.vault.biometricsEnabled {
                        Button {
                            Task { await model.tryBiometricUnlock() }
                        } label: {
                            Label("Unlock with \(Biometry.name)", systemImage: "faceid")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Lock now") {
                        model.vault.lock()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlassBackground(material: .underWindowBackground, bloom: 0.5))
            .navigationTitle("Sensitive items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Offer Face ID the moment the sheet opens, so unlocking is a glance
                // rather than a tap and then a glance.
                if !model.vault.isUnlocked, model.vault.biometricsEnabled {
                    await model.tryBiometricUnlock()
                }
            }
            .onChange(of: model.vault.isUnlocked) { _, unlocked in
                if unlocked { secret = ""; error = nil }
            }
        }
    }

    private func unlock() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await model.vault.unlock(secret: secret)
            error = nil
            secret = ""
        } catch {
            self.error = error.localizedDescription
            secret = ""
        }
    }
}
#endif
