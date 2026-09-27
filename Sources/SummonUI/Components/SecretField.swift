import SwiftUI
import SummonKit

/// The entry field for the vault's PIN.
///
/// One view rather than a `PINField` at every call site, because there are five
/// places that ask for the PIN and they were already prone to disagreeing about
/// wording and about whether return was needed. Four digits resolve on the fourth,
/// which is what makes the PIN feel like no step at all.
public struct SecretField: View {
    @Binding var secret: String
    let isError: Bool
    let onComplete: () -> Void

    public init(secret: Binding<String>, isError: Bool = false,
                onComplete: @escaping () -> Void = {}) {
        _secret = secret
        self.isError = isError
        self.onComplete = onComplete
    }

    public var body: some View {
        PINField(digits: $secret, isError: isError, onComplete: onComplete)
    }
}
