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

    /// When the last wrong guess happened, and the only clock the cooldown trusts.
    ///
    /// This replaces an absolute `lockedUntil`, which was a wall-clock deadline and so
    /// cleared itself if the system clock was set back. Elapsed time is measured from
    /// here instead, and a clock moved backwards reads as no time passed at all — so
    /// fiddling with it can only ever lengthen the wait. A `lockedUntil` in an older
    /// wrapper is ignored on decode, which forgets a cooldown that was pending at
    /// upgrade; that is one free attempt, once, and worth the simpler rule.
    var lastFailedAt: Date?

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
        let kek = try derive(secret: secret, salt: wrapper.salt,
                             iterations: wrapper.safeIterations)
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
