import AppKit
import SwiftUI
import SummonKit

/// The secret and Touch ID, inline in the panel. Unlocking should not mean going
/// somewhere else.
public struct UnlockPane: View {
    @Bindable var model: AppModel
    let pendingItemID: UUID?

    public init(model: AppModel, pendingItemID: UUID?) {
        self.model = model
        self.pendingItemID = pendingItemID
    }

    public var body: some View {
        VStack(spacing: Theme.Space.m) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.selection)
                    .frame(width: 58, height: 58)
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            VStack(spacing: Theme.Space.xxs) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                Text(subhead)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            // The same field as everywhere else, in whichever shape this vault uses.
            SecretField(kind: model.vault.secretKind,
                        secret: $model.secretEntry,
                        isError: model.secretError != nil,
                        onComplete: { model.submitSecret() })

            if let error = model.secretError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .labelStyle(.titleAndIcon)
            }

            HStack(spacing: Theme.Space.xs) {
                if model.vault.biometricsEnabled {
                    Button {
                        Task { await model.tryBiometricUnlock() }
                    } label: {
                        Label("Touch ID", systemImage: "touchid")
                    }
                    .buttonStyle(.bordered)
                }

                Button("Cancel") { model.mode = .search }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.l)
    }

    private var headline: String {
        pendingItemID == nil ? "Unlock sensitive items" : "This item is locked"
    }

    private var subhead: String {
        if let until = model.vault.throttledUntil {
            let seconds = max(1, Int(until.timeIntervalSinceNow.rounded(.up)))
            return "Too many attempts. Try again in \(seconds)s."
        }
        let noun = model.vault.secretKind.noun
        if model.vault.biometricsEnabled {
            return "Use Touch ID, or enter your \(noun). Contents stay encrypted on this Mac until you do."
        }
        return "Enter your \(noun). Contents stay encrypted on this Mac until you do."
    }
}
