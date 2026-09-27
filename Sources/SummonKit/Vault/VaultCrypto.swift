import CommonCrypto
import CryptoKit
import Foundation

/// The shape of a PIN, in one place so the field and the validator cannot disagree.
public enum PINPolicy {
    public static let length = 4

    /// Exactly four digits.
    ///
    /// Fixed-length so the entry field can be four boxes that fill and move on by
    /// themselves, with no separate "done" step to reach for.
    public static func isValid(_ pin: String) -> Bool {
        pin.count == length && pin.allSatisfy(\.isNumber)
    }
}

public enum VaultError: Error, Equatable, LocalizedError {
    case notConfigured
    case locked
    case wrongPIN
    case pinNotFourDigits
    case throttled(retryAfter: TimeInterval)
    case biometricsUnavailable
    case biometricsFailed(String)
    case corruptWrapper
    case keyDerivationFailed

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "No PIN has been set up yet."
        case .locked: "The vault is locked."
        case .wrongPIN: "That is not correct."
        case .pinNotFourDigits: "A PIN is four digits."
        case .throttled(let t): "Too many attempts. Try again in \(Int(ceil(t))) seconds."
        case .biometricsUnavailable: "\(Biometry.name) isn’t available on \(Biometry.deviceName)."
        case .biometricsFailed(let m): m
        case .corruptWrapper: "The vault key file is damaged."
        case .keyDerivationFailed: "Could not derive a key from that."
        }
    }
}

/// The key that actually seals content. Held only while the vault is unlocked.
///
/// Every item gets its own key derived from the master via HKDF with the item's
/// UUID as `info`, so no key is ever reused across two items.
public struct VaultKey: Sendable, Equatable {
    private let master: Data

    init(master: Data) { self.master = master }

    static func generate() -> VaultKey {
        VaultKey(master: Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }))
    }

    var masterBytes: Data { master }

    private func itemKey(_ itemID: UUID) -> SymmetricKey {
        var info = Data("summon.item.v1.".utf8)
        withUnsafeBytes(of: itemID.uuid) { info.append(contentsOf: $0) }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: master),
            salt: Data("summon.hkdf.salt.v1".utf8),
            info: info,
            outputByteCount: 32
        )
    }

    public func seal(_ data: Data, itemID: UUID) throws -> Data {
        let box = try AES.GCM.seal(data, using: itemKey(itemID))
        guard let combined = box.combined else { throw VaultError.corruptWrapper }
        return combined
    }

    public func open(_ data: Data, itemID: UUID) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: itemKey(itemID))
    }

    public func seal(_ text: String, itemID: UUID) throws -> Data {
        try seal(Data(text.utf8), itemID: itemID)
    }

    public func openText(_ data: Data, itemID: UUID) throws -> String {
        String(decoding: try open(data, itemID: itemID), as: UTF8.self)
    }
}

/// On-disk wrapper: the master key sealed under a key derived from the PIN and, where
/// the Keychain allows it, a secret that never leaves this device.
struct VaultWrapper: Codable, Sendable {
    var version: Int = 1
    var salt: Data
    var iterations: Int
    var sealedMaster: Data
    var failedAttempts: Int = 0

    /// When the last wrong guess happened, and the only clock the cooldown trusts.
    ///
    /// This replaces an absolute `lockedUntil`, which was a wall-clock deadline and so
    /// cleared itself if the system clock was set back. Elapsed time is measured from
    /// here instead, and a clock moved backwards reads as no time passed at all — so
    /// fiddling with it can only ever lengthen the wait. A `lockedUntil` in an older
    /// wrapper is ignored on decode, which forgets a cooldown that was pending at
    /// upgrade; that is one free attempt, once, and worth the simpler rule.
    var lastFailedAt: Date?

    /// Whether the key sealing the master also needs this device's secret.
    ///
    /// Four digits is 10,000 guesses. The cooldown makes that acceptable for someone
    /// typing into the app, but anyone holding a copy of `vault.wrap` — from a backup,
    /// say — could guess offline as fast as their hardware allows. Mixing in a random
    /// secret that stays in this device's Keychain makes the file on its own worthless.
    ///
    /// Optional so a wrapper written before this existed still decodes: the
    /// synthesised decoder fails on a missing key rather than defaulting, which would
    /// lock every existing vault out. Those wrappers are PIN-only, and are rewrapped
    /// on their next successful unlock.
    var deviceBound: Bool?

    var isDeviceBound: Bool { deviceBound == true }

    static let defaultIterations = 600_000

    /// Bounds on the iteration count read back from disk.
    ///
    /// `iterations` is a plain number in a file the app does not control, and it is fed
    /// straight to PBKDF2. The ceiling is what matters: a wrapper claiming two billion
    /// rounds is not a slow unlock, it is a hang with no way out. The floor is mostly
    /// tidiness — someone who can edit the field can already guess offline — but it
    /// stops a tampered-down file making guesses through the app cheap too.
    static let minimumIterations = 1_000
    static let maximumIterations = 4_000_000

    /// The count actually handed to the KDF.
    var safeIterations: Int {
        min(max(iterations, VaultWrapper.minimumIterations), VaultWrapper.maximumIterations)
    }
}

enum VaultCrypto {
    /// PBKDF2-SHA256. CryptoKit has no password-based KDF, so this uses CommonCrypto.
    static func derive(secret: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var secretBytes = Array(secret.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        // Wiped on the way out. These two are the only key material here held in
        // buffers this code fully owns — a `[UInt8]` it allocated and nothing else has
        // a reference to — so zeroing them actually means something. The master key
        // itself lives in a `Data`, which copy-on-write may have duplicated anywhere,
        // and pretending to scrub that would be theatre; the Hardened Runtime is what
        // keeps another process from reading it.
        defer {
            secretBytes.resetBytes(in: secretBytes.indices)
            out.resetBytes(in: out.indices)
        }

        let status = salt.withUnsafeBytes { saltBuf -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                secretBytes, secretBytes.count,
                saltBuf.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPBKDFAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &out, out.count
            )
        }
        guard status == kCCSuccess else { throw VaultError.keyDerivationFailed }
        return SymmetricKey(data: Data(out))
    }

    /// `derive`, off whatever actor called it.
    ///
    /// 600,000 rounds of PBKDF2 is a few hundred milliseconds. `Vault` is
    /// `@MainActor` and this used to be a synchronous call, which runs on the caller's
    /// actor — so every unlock spent that long with the main thread blocked, freezing
    /// the panel at the exact moment someone is typing into it.
    static func deriveOffMain(
        secret: String,
        salt: Data,
        iterations: Int
    ) async throws -> SymmetricKey {
        try await offMain { try derive(secret: secret, salt: salt, iterations: iterations) }
    }

    /// Runs `work` somewhere other than the caller's actor.
    ///
    /// Named and separated so the guarantee can be tested directly. Timing the main
    /// actor's responsiveness cannot do it: the suite runs its tests in parallel, so
    /// other main-actor work dominates the measurement, and a build with derivation
    /// deliberately pinned to the main actor measures the same as a correct one.
    ///
    /// A nonisolated `async` function would already hop off the caller's actor, which
    /// makes the detached task redundant today — but that is a property of where this
    /// code happens to sit, and giving `VaultCrypto` an actor later would silently undo
    /// it. This states the requirement instead of inheriting it.
    static func offMain<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }

    /// The PIN's key, bound to this device when there is a device secret to bind to.
    ///
    /// PBKDF2 still does the slow part, so a guess through the app costs what it
    /// always did. The device secret goes in afterwards as HKDF salt: without it the
    /// output is unrelated to the real key, however many PINs are tried.
    static func keyEncryptionKey(
        secret: String,
        salt: Data,
        iterations: Int,
        deviceSecret: Data?
    ) async throws -> SymmetricKey {
        let stretched = try await deriveOffMain(secret: secret, salt: salt, iterations: iterations)
        guard let deviceSecret else { return stretched }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: stretched,
                                      salt: deviceSecret,
                                      info: Data("summon.kek.device.v1".utf8),
                                      outputByteCount: 32)
    }

    static func wrap(
        master: VaultKey,
        secret: String,
        deviceSecret: Data? = nil,
        iterations: Int = VaultWrapper.defaultIterations
    ) async throws -> VaultWrapper {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let kek = try await keyEncryptionKey(secret: secret, salt: salt, iterations: iterations,
                                             deviceSecret: deviceSecret)
        let box = try AES.GCM.seal(master.masterBytes, using: kek)
        guard let combined = box.combined else { throw VaultError.corruptWrapper }
        return VaultWrapper(salt: salt, iterations: iterations, sealedMaster: combined,
                            deviceBound: deviceSecret != nil)
    }

    static func unwrap(_ wrapper: VaultWrapper, secret: String, deviceSecret: Data? = nil) async throws -> VaultKey {
        let kek = try await keyEncryptionKey(secret: secret, salt: wrapper.salt,
                                             iterations: wrapper.safeIterations,
                                             deviceSecret: wrapper.isDeviceBound ? deviceSecret : nil)
        do {
            let box = try AES.GCM.SealedBox(combined: wrapper.sealedMaster)
            return VaultKey(master: try AES.GCM.open(box, using: kek))
        } catch {
            // An authentication failure here means the secret was wrong, not that the
            // file is damaged — AES-GCM's tag is what verifies it.
            throw VaultError.wrongPIN
        }
    }
}
