import AppKit
import SwiftUI
import SummonKit
import SummonUI

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
                    // `Theme.selection` until the accent landed, at which point the
                    // unlock prompt started wearing the colour that means "you are here".
                    .fill(Theme.surface)
                    .frame(width: 58, height: 58)
                Image(systemName: "lock.fill")
                    .font(Theme.Icon.hero.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            VStack(spacing: Theme.Space.xxs) {
                Text(headline)
                    .font(Theme.Typography.heading.weight(.semibold))
                Text(subhead)
                    .font(Theme.Typography.caption)
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
                StatusBadge(error, tone: .danger)
            }

            HStack(spacing: Theme.Space.xs) {
                if model.vault.biometricsEnabled {
                    Button {
                        Task { await model.tryBiometricUnlock() }
                    } label: {
                        Label("Touch ID", systemImage: "touchid")
                    }
                    .buttonStyle(.summonQuiet)
                }

                Button("Cancel") { model.mode = .search }
                    .buttonStyle(.summonQuiet)
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
