import Foundation
import LocalAuthentication

#if canImport(UIKit)
import UIKit
#endif

/// What to call the thing that unlocks the vault, and the device it belongs to.
///
/// The vault's messages used to say "Touch ID" and "this Mac" outright, which was
/// true of the only platform that existed. On a phone both halves are wrong.
public enum Biometry {
    /// "Face ID", "Touch ID", "Optic ID", or a neutral word when there is none.
    public static var name: String {
        let context = LAContext()
        // `biometryType` is only populated once a policy has been evaluated for
        // availability; read without this it reports `.none` on a perfectly capable
        // device.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "biometric unlock"
        }
    }

    /// "this Mac", "this iPhone", "this iPad" — for messages about what a device has.
    public static var deviceName: String {
        #if os(macOS)
        "this Mac"
        #elseif canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: "this iPad"
        case .phone: "this iPhone"
        default: "this device"
        }
        #else
        "this device"
        #endif
    }
}
