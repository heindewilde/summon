import AppKit
import SwiftUI
import SummonKit

/// PIN and Touch ID, inline in the panel. Unlocking should not mean going somewhere else.
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

            // The same four boxes as everywhere else, resolving on the fourth digit.
            PINField(digits: $model.pinEntry,
                     isError: model.pinError != nil,
                     onComplete: { model.submitPIN() })

            if let error = model.pinError {
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
        if model.vault.biometricsEnabled {
            return "Use Touch ID, or enter your PIN. Contents stay encrypted on this Mac until you do."
        }
        return "Enter your PIN. Contents stay encrypted on this Mac until you do."
    }
}
