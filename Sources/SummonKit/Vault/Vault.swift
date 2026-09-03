import Foundation
import LocalAuthentication
import Observation
import Security

public enum VaultState: Equatable, Sendable {
    case notConfigured
    case locked
    case unlocked
}

/// Holds the master key while unlocked, and nothing at all while locked.
///
/// The master key is wrapped two independent ways — under the PIN (PBKDF2) and in the
/// Keychain behind Touch ID — so changing the PIN is instant (it re-wraps one key)
/// and losing biometrics never loses data.
@MainActor
@Observable
public final class Vault {
    public private(set) var state: VaultState = .notConfigured
    public private(set) var biometricsEnabled: Bool = false
    public private(set) var lastError: String?

    /// Minutes of inactivity before the vault relocks. 0 means never.
    public var autoLockMinutes: Int = 5

    private let paths: LibraryPaths
    private var key: VaultKey?
    private var wrapper: VaultWrapper?
    private var lastActivity = Date()

    private let keychainService = "com.heindewilde.summon.vault"
    private let keychainAccount = "master-key"

    public init(paths: LibraryPaths) {
        self.paths = paths
        reload()
    }

    // MARK: - Lifecycle

    public func reload() {
        if let data = try? Data(contentsOf: paths.vaultKeyFile),
           let w = try? JSONDecoder().decode(VaultWrapper.self, from: data) {
            wrapper = w
            state = .locked
        } else {
            wrapper = nil
            state = .notConfigured
        }
        biometricsEnabled = keychainHasKey()
    }

    public var isConfigured: Bool { state != .notConfigured }
    public var isUnlocked: Bool { state == .unlocked }

    /// The key for sealing and opening content. Nil unless unlocked.
    public var currentKey: VaultKey? { state == .unlocked ? key : nil }

    // MARK: - Setup

    /// Whether this vault is opened by a PIN or a passphrase.
    public var secretKind: VaultSecretKind { wrapper?.kind ?? .pin }

    public func setUpSecret(_ secret: String, kind: VaultSecretKind) throws {
        guard VaultSecretPolicy.isValid(secret, kind: kind) else {
            throw VaultSecretPolicy.violation(for: kind)
        }
        let master = VaultKey.generate()
        let w = try VaultCrypto.wrap(master: master, secret: secret, kind: kind)
        try persist(w)
        wrapper = w
        key = master
        state = .unlocked
        lastActivity = Date()
    }

    public func setUpPIN(_ pin: String) throws {
        try setUpSecret(pin, kind: .pin)
    }

    /// Re-wraps the one master key under a new secret, optionally of a different kind.
    ///
    /// Switching between a PIN and a passphrase is this same operation: nothing is
    /// decrypted and nothing is rewritten, because the key sealing the content never
    /// changes — only the key sealing *it* does.
    public func changeSecret(current: String, new: String, kind: VaultSecretKind? = nil) throws {
        guard let w = wrapper else { throw VaultError.notConfigured }
        let newKind = kind ?? w.kind
        guard VaultSecretPolicy.isValid(new, kind: newKind) else {
            throw VaultSecretPolicy.violation(for: newKind)
        }
        let master = try unwrapCounting(w, secret: current)
        let fresh = try VaultCrypto.wrap(master: master, secret: new, kind: newKind)
        try persist(fresh)
        wrapper = fresh
        key = master
        state = .unlocked
        lastActivity = Date()
    }

    public func changePIN(current: String, new: String) throws {
        try changeSecret(current: current, new: new, kind: .pin)
    }

    /// Removes PIN protection entirely. Callers must decrypt content back to
    /// plaintext *before* calling this, or it becomes unreadable.
    public func removePIN() throws {
        try? FileManager.default.removeItem(at: paths.vaultKeyFile)
        disableBiometricUnlock()
        wrapper = nil
        key = nil
        state = .notConfigured
    }

    // MARK: - Unlock / lock

    public func unlock(secret: String) throws {
        guard let w = wrapper else { throw VaultError.notConfigured }
        key = try unwrapCounting(w, secret: secret)
        state = .unlocked
        lastActivity = Date()
        lastError = nil
    }

    public func unlock(pin: String) throws {
        try unlock(secret: pin)
    }

    /// Unwraps a guess, and holds the cooldown to it.
    ///
    /// Every path that takes a guess at the secret comes through here, so no caller
    /// can win a free attempt by choosing the other one. `changeSecret` used to unwrap
    /// directly, which made "change my PIN" an unthrottled oracle for the current one.
    private func unwrapCounting(_ existing: VaultWrapper, secret: String) throws -> VaultKey {
        var w = existing

        if let remaining = Vault.remainingCooldown(w) {
            throw VaultError.throttled(retryAfter: remaining)
        }

        do {
            let master = try VaultCrypto.unwrap(w, secret: secret)
            w.failedAttempts = 0
            w.lastFailedAt = nil
            try? persist(w)
            wrapper = w
            return master
        } catch {
            w.failedAttempts += 1
            w.lastFailedAt = Date()
            try? persist(w)
            wrapper = w
            throw VaultError.wrongPIN
        }
    }

    /// Wrong guesses tolerated before the cooldown starts.
    static let attemptsBeforeCooldown = 5

    /// Escalating cooldown: 30s, 60s, 120s, capped at five minutes.
    static func cooldown(afterFailures failures: Int) -> TimeInterval {
        guard failures >= attemptsBeforeCooldown else { return 0 }
        let over = failures - (attemptsBeforeCooldown - 1)
        return min(300, 30 * pow(2, Double(over - 1)))
    }

    /// How much longer the cooldown has to run, or nil if it has expired.
    ///
    /// Measured forwards from the last wrong guess rather than against a stored
    /// deadline. A deadline is wall-clock, so setting the system clock back cleared
    /// it; measuring elapsed time means a clock moved backwards looks like no time
    /// has passed, and the wait can only ever get longer.
    static func remainingCooldown(_ w: VaultWrapper, now: Date = Date()) -> TimeInterval? {
        let required = cooldown(afterFailures: w.failedAttempts)
        guard required > 0, let last = w.lastFailedAt else { return nil }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed < required else { return nil }
        return required - max(0, elapsed)
    }

    public func lock() {
        key = nil
        if wrapper != nil { state = .locked }
    }

    /// Call whenever the user interacts, to defer the auto-lock.
    public func noteActivity() { lastActivity = Date() }

    /// Drive from a timer in the app layer. Returns true if it relocked.
    @discardableResult
    public func lockIfIdle(now: Date = Date()) -> Bool {
        guard state == .unlocked, autoLockMinutes > 0 else { return false }
        guard now.timeIntervalSince(lastActivity) >= Double(autoLockMinutes) * 60 else { return false }
        lock()
        return true
    }

    public var failedAttempts: Int { wrapper?.failedAttempts ?? 0 }

    public var throttledUntil: Date? {
        guard let w = wrapper, let remaining = Vault.remainingCooldown(w) else { return nil }
        return Date().addingTimeInterval(remaining)
    }

    // MARK: - Biometrics

    /// Whether this Mac has usable biometric hardware.
    public static var biometricsAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    private static var storageProbe: Bool?

    /// Whether the Keychain will actually accept a biometry-protected item.
    ///
    /// Having a Touch ID sensor is not enough. An item guarded by `SecAccessControl`
    /// lives in the data-protection keychain, which requires a `keychain-access-groups`
    /// entitlement prefixed with an Apple Team ID. A locally-signed build has no team,
    /// and adding the entitlement unprefixed makes the app fail to launch — so the
    /// honest answer is to detect this and not offer the feature.
    public static var biometricStorageAvailable: Bool {
        if let cached = storageProbe { return cached }
        guard biometricsAvailable else {
            storageProbe = false
            return false
        }
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil
        ) else {
            storageProbe = false
            return false
        }

        let probeAccount = "biometric-probe"
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.heindewilde.summon.vault",
            kSecAttrAccount as String: probeAccount,
        ]
        SecItemDelete(base as CFDictionary)

        var attrs = base
        attrs[kSecValueData as String] = Data([0])
        attrs[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(attrs as CFDictionary, nil)
        SecItemDelete(base as CFDictionary)

        let ok = status == errSecSuccess
        if !ok {
            Log.vault.info("Biometric key storage unavailable (status \(status)).")
        }
        storageProbe = ok
        return ok
    }

    public func enableBiometricUnlock() throws {
        guard let key else { throw VaultError.locked }
        guard Vault.biometricStorageAvailable else { throw VaultError.biometricsUnavailable }

        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &acError
        ) else {
            throw VaultError.biometricsFailed("Could not create an access policy.")
        }

        deleteKeychainItem()
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: key.masterBytes,
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.biometricsFailed("Keychain refused to store the key (\(status)).")
        }
        biometricsEnabled = true
    }

    public func disableBiometricUnlock() {
        deleteKeychainItem()
        biometricsEnabled = false
    }

    public func unlockWithBiometrics(reason: String = "unlock your sensitive items") async throws {
        guard biometricsEnabled else { throw VaultError.biometricsUnavailable }

        let context = LAContext()
        context.localizedReason = reason
        let service = keychainService
        let account = keychainAccount

        // SecItemCopyMatching blocks while the Touch ID sheet is up, so keep it off main.
        let data: Data = try await Task.detached(priority: .userInitiated) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecUseAuthenticationContext as String: context,
            ]
            var out: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &out)
            guard status == errSecSuccess, let d = out as? Data else {
                if status == errSecUserCanceled {
                    throw VaultError.biometricsFailed("Cancelled.")
                }
                throw VaultError.biometricsFailed("Touch ID could not release the key (\(status)).")
            }
            return d
        }.value

        key = VaultKey(master: data)
        state = .unlocked
        lastActivity = Date()
        lastError = nil
    }

    // MARK: - Private

    private func persist(_ w: VaultWrapper) throws {
        let data = try JSONEncoder().encode(w)
        try data.write(to: paths.vaultKeyFile, options: .atomic)
    }

    private func keychainHasKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: false,
            // Do not trigger a Touch ID prompt merely to check for existence.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private func deleteKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
