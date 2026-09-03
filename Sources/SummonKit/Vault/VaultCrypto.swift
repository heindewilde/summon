import CommonCrypto
import CryptoKit
import Foundation

/// How the vault is unlocked.
///
/// A PIN is the default because it is what the summon moment wants: four boxes that
/// fill themselves, no "done" step, no shift key. A passphrase exists because four
/// digits is 10,000 combinations, and the cooldown that makes that acceptable only
/// applies to someone going through the app. Anyone holding `vault.wrap` can guess
/// offline as fast as their hardware allows, and at that speed 10,000 is not a wait.
public enum VaultSecretKind: String, Codable, Sendable, CaseIterable, Equatable {
    case pin
    case passphrase

    public var displayName: String {
        switch self {
        case .pin: "PIN"
        case .passphrase: "Passphrase"
        }
    }

    /// Sentence-case, for use mid-sentence: "Enter your passphrase".
    public var noun: String {
        switch self {
        case .pin: "PIN"
        case .passphrase: "passphrase"
        }
    }
}

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

/// The shape of a passphrase.
public enum PassphrasePolicy {
    /// Twelve is the shortest length at which a passphrase is worth the trouble of
    /// typing over a PIN: below it, the offline guessing that motivates the option in
    /// the first place is still cheap enough to be worth an attacker's while.
    public static let minimumLength = 12

    public static func isValid(_ passphrase: String) -> Bool {
        passphrase.count >= minimumLength
    }
}

/// One validator, so no caller has to know which policy applies.
public enum VaultSecretPolicy {
    public static func isValid(_ secret: String, kind: VaultSecretKind) -> Bool {
        switch kind {
        case .pin: PINPolicy.isValid(secret)
        case .passphrase: PassphrasePolicy.isValid(secret)
        }
    }

    /// The error to raise when `isValid` says no.
    public static func violation(for kind: VaultSecretKind) -> VaultError {
        switch kind {
        case .pin: .pinNotFourDigits
        case .passphrase: .passphraseTooShort
        }
    }
}

public enum VaultError: Error, Equatable, LocalizedError {
    case notConfigured
    case locked
    case wrongPIN
    case pinNotFourDigits
    case passphraseTooShort
    case throttled(retryAfter: TimeInterval)
    case biometricsUnavailable
    case biometricsFailed(String)
    case corruptWrapper
    case keyDerivationFailed

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "No PIN or passphrase has been set up yet."
        case .locked: "The vault is locked."
        case .wrongPIN: "That is not correct."
        case .pinNotFourDigits: "A PIN is four digits."
        case .passphraseTooShort: "A passphrase is at least \(PassphrasePolicy.minimumLength) characters."
        case .throttled(let t): "Too many attempts. Try again in \(Int(ceil(t))) seconds."
        case .biometricsUnavailable: "Touch ID isn’t available on this Mac."
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

/// On-disk wrapper: the master key sealed under a key derived from the secret.
struct VaultWrapper: Codable, Sendable {
    var version: Int = 1
    var salt: Data
    var iterations: Int
    var sealedMaster: Data
    var failedAttempts: Int = 0
    var lockedUntil: Date?

    /// Which kind of secret opens this wrapper.
    ///
    /// Optional and read through `kind`, so a wrapper written before passphrases
    /// existed still decodes — every one of those was a PIN. A defaulted
    /// non-optional would not do: the synthesised decoder fails on a missing key
    /// rather than falling back, which would lock every existing vault out.
    var kindRaw: String?

    var kind: VaultSecretKind {
        kindRaw.flatMap(VaultSecretKind.init(rawValue:)) ?? .pin
    }

    static let defaultIterations = 600_000
}

enum VaultCrypto {
    /// PBKDF2-SHA256. CryptoKit has no password-based KDF, so this uses CommonCrypto.
    static func derive(secret: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let secretBytes = Array(secret.utf8)
        var out = [UInt8](repeating: 0, count: 32)
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

    static func wrap(
        master: VaultKey,
        secret: String,
        kind: VaultSecretKind = .pin,
        iterations: Int = VaultWrapper.defaultIterations
    ) throws -> VaultWrapper {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let kek = try derive(secret: secret, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(master.masterBytes, using: kek)
        guard let combined = box.combined else { throw VaultError.corruptWrapper }
        return VaultWrapper(salt: salt, iterations: iterations, sealedMaster: combined,
                            kindRaw: kind.rawValue)
    }

    static func unwrap(_ wrapper: VaultWrapper, secret: String) throws -> VaultKey {
        let kek = try derive(secret: secret, salt: wrapper.salt, iterations: wrapper.iterations)
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
