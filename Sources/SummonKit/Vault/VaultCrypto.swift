import CommonCrypto
import CryptoKit
import Foundation

/// The shape of a PIN, in one place so the field and the validator cannot disagree.
public enum PINPolicy {
    public static let length = 4

    /// Exactly four digits.
    ///
    /// Fixed-length so the entry field can be four boxes that fill and move on by
    /// themselves, with no separate "done" step to reach for. Four digits is only
    /// 10,000 combinations, which is why the key derivation is deliberately slow and
    /// why five wrong attempts start a cooldown — the length is a usability choice
    /// held up by the two mechanisms either side of it, not on its own.
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
        case .wrongPIN: "That PIN is not correct."
        case .pinNotFourDigits: "A PIN is four digits."
        case .throttled(let t): "Too many attempts. Try again in \(Int(ceil(t))) seconds."
        case .biometricsUnavailable: "Touch ID isn’t available on this Mac."
        case .biometricsFailed(let m): m
        case .corruptWrapper: "The vault key file is damaged."
        case .keyDerivationFailed: "Could not derive a key from that PIN."
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

/// On-disk wrapper: the master key sealed under a PIN-derived key.
struct VaultWrapper: Codable, Sendable {
    var version: Int = 1
    var salt: Data
    var iterations: Int
    var sealedMaster: Data
    var failedAttempts: Int = 0
    var lockedUntil: Date?

    static let defaultIterations = 600_000
}

enum VaultCrypto {
    /// PBKDF2-SHA256. CryptoKit has no password-based KDF, so this uses CommonCrypto.
    static func derive(pin: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let pinBytes = Array(pin.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuf -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pinBytes, pinBytes.count,
                saltBuf.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPBKDFAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &out, out.count
            )
        }
        guard status == kCCSuccess else { throw VaultError.keyDerivationFailed }
        return SymmetricKey(data: Data(out))
    }

    static func wrap(master: VaultKey, pin: String, iterations: Int = VaultWrapper.defaultIterations) throws -> VaultWrapper {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let kek = try derive(pin: pin, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(master.masterBytes, using: kek)
        guard let combined = box.combined else { throw VaultError.corruptWrapper }
        return VaultWrapper(salt: salt, iterations: iterations, sealedMaster: combined)
    }

    static func unwrap(_ wrapper: VaultWrapper, pin: String) throws -> VaultKey {
        let kek = try derive(pin: pin, salt: wrapper.salt, iterations: wrapper.iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: wrapper.sealedMaster)
            return VaultKey(master: try AES.GCM.open(box, using: kek))
        } catch {
            // An authentication failure here means the PIN was wrong, not that the
            // file is damaged — AES-GCM's tag is what verifies the PIN.
            throw VaultError.wrongPIN
        }
    }

    static func isValidPIN(_ pin: String) -> Bool { PINPolicy.isValid(pin) }
}
