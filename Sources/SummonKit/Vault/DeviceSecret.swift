import Foundation
import Security

/// Where the vault keeps the random secret that binds its PIN to this device.
///
/// See `VaultWrapper.deviceBound` for why it exists. A protocol so tests can hold the
/// secret in memory: `swift test` runs unsigned, and an unsigned process may not use
/// the data-protection keychain at all.
public protocol DeviceSecretStore: AnyObject, Sendable {
    func load() -> Data?
    /// True only when the store says for certain there is no secret — not when it
    /// could not be read. A keychain that is merely unavailable (before first unlock,
    /// say) must never be taken as a secret that is gone.
    func isKnownMissing() -> Bool
    /// False when the store refused it, in which case the vault stays PIN-only.
    func save(_ secret: Data) -> Bool
    func delete()
}

/// The real store: one item in the data-protection keychain.
///
/// `ThisDeviceOnly`, so it is in no backup that restores elsewhere and never reaches
/// iCloud — which is the whole point. The PIN is per-device already (each device
/// wraps the shared master key itself), so nothing else needs to see this.
public final class KeychainDeviceSecret: DeviceSecretStore {
    private let account: String

    public init(isDemo: Bool = LibraryPaths.isDemoMode) {
        // The demo library has its own vault, and must not share or clobber the
        // real one's secret.
        account = isDemo ? "device-secret-demo" : "device-secret"
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.heindewilde.summon.vault",
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: "JV4MVRB77Q.com.heindewilde.summon",
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func load() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public func isKnownMissing() -> Bool {
        var q = query
        q[kSecReturnData as String] = false
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecItemNotFound
    }

    public func save(_ secret: Data) -> Bool {
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = secret
        // After first unlock, matching the synced master key: an extension may need
        // to unlock with the screen locked.
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            Log.vault.warning("Could not store the device secret (status \(status)); the PIN stays unbound.")
        }
        return status == errSecSuccess
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests.
public final class InMemoryDeviceSecret: DeviceSecretStore, @unchecked Sendable {
    private var secret: Data?
    public init(_ secret: Data? = nil) { self.secret = secret }
    public func load() -> Data? { secret }
    public func isKnownMissing() -> Bool { secret == nil }
    public func save(_ secret: Data) -> Bool { self.secret = secret; return true }
    public func delete() { secret = nil }
}
