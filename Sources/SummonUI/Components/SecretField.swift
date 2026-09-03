import SwiftUI
import SummonKit

/// The entry field for whichever kind of secret this vault uses.
///
/// One view rather than two branches at every call site, because there are five
/// places that ask for the secret and they were already prone to disagreeing about
/// wording and about whether return was needed.
///
/// The two kinds resolve differently on purpose. Four digits resolve on the fourth,
/// which is what makes the PIN feel like no step at all. A passphrase has no known
/// length, so it resolves on return — and says so, since nothing else on screen would.
public struct SecretField: View {
    let kind: VaultSecretKind
    @Binding var secret: String
    let isError: Bool
    let onComplete: () -> Void

    @FocusState private var focused: Bool

    public init(kind: VaultSecretKind, secret: Binding<String>, isError: Bool = false,
                onComplete: @escaping () -> Void = {}) {
        self.kind = kind
        _secret = secret
        self.isError = isError
        self.onComplete = onComplete
    }

    public var body: some View {
        switch kind {
        case .pin:
            PINField(digits: $secret, isError: isError, onComplete: onComplete)
        case .passphrase:
            VStack(spacing: Theme.Space.xxs) {
                SecureField("Passphrase", text: $secret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .focused($focused)
                    .frame(width: 260)
                    .onSubmit(onComplete)
                    .overlay {
                        if isError {
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .strokeBorder(Theme.danger, lineWidth: 1)
                        }
                    }
                Text("Press return when you’re done.")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .onAppear {
                // The same beat the PIN field needs: a sheet is not in the responder
                // chain on its first pass, so focusing immediately is dropped.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    focused = true
                }
            }
        }
    }
}
