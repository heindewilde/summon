import Foundation
import Testing
@testable import SummonKit

@Suite("Vault crypto")
struct VaultCryptoTests {
    // Tests use a low iteration count so the suite stays fast; production uses 600k.
    let iters = 1_000

    @Test("Master key round-trips through a PIN wrap")
    func wrapUnwrapRoundTrip() throws {
        let master = VaultKey.generate()
        let wrapper = try VaultCrypto.wrap(master: master, pin: "482913", iterations: iters)
        let recovered = try VaultCrypto.unwrap(wrapper, pin: "482913")
        #expect(recovered == master)
    }

    @Test("A wrong PIN is rejected, not silently mis-decrypted")
    func wrongPINRejected() throws {
        let wrapper = try VaultCrypto.wrap(master: .generate(), pin: "1234", iterations: iters)
        #expect(throws: VaultError.wrongPIN) {
            _ = try VaultCrypto.unwrap(wrapper, pin: "1235")
        }
    }

    @Test("Each wrap uses a fresh salt, so the same PIN yields different ciphertext")
    func saltsAreUnique() throws {
        let master = VaultKey.generate()
        let a = try VaultCrypto.wrap(master: master, pin: "1234", iterations: iters)
        let b = try VaultCrypto.wrap(master: master, pin: "1234", iterations: iters)
        #expect(a.salt != b.salt)
        #expect(a.sealedMaster != b.sealedMaster)
        let ua = try VaultCrypto.unwrap(a, pin: "1234")
        let ub = try VaultCrypto.unwrap(b, pin: "1234")
        #expect(ua == ub)
    }

    @Test("Content seals and opens under the item's own key")
    func sealOpenRoundTrip() throws {
        let key = VaultKey.generate()
        let id = UUID()
        let secret = "Passport number 1234567 — do not paste into a browser."
        let sealed = try key.seal(secret, itemID: id)
        #expect(sealed != Data(secret.utf8))
        #expect(try key.openText(sealed, itemID: id) == secret)
    }

    @Test("An item's ciphertext cannot be opened with another item's key")
    func perItemKeysAreDistinct() throws {
        let key = VaultKey.generate()
        let a = UUID(), b = UUID()
        let sealed = try key.seal("shared master, different item", itemID: a)
        #expect(throws: (any Error).self) {
            _ = try key.open(sealed, itemID: b)
        }
    }

    @Test("Sealing the same plaintext twice produces different ciphertext")
    func nonceIsFresh() throws {
        let key = VaultKey.generate()
        let id = UUID()
        let one = try key.seal("same input", itemID: id)
        let two = try key.seal("same input", itemID: id)
        #expect(one != two)
        #expect(try key.openText(one, itemID: id) == "same input")
        #expect(try key.openText(two, itemID: id) == "same input")
    }

    @Test("Tampering with the ciphertext is detected")
    func tamperDetected() throws {
        let key = VaultKey.generate()
        let id = UUID()
        var sealed = try key.seal("authentic", itemID: id)
        sealed[sealed.count - 1] ^= 0xFF
        #expect(throws: (any Error).self) {
            _ = try key.open(sealed, itemID: id)
        }
    }

    @Test("PIN policy accepts 4–12 digits and nothing else",
          arguments: [("1234", true), ("482913", true), ("123", false),
                      ("1234567890123", false), ("12a4", false), ("", false)])
    func pinPolicy(pin: String, valid: Bool) {
        #expect(VaultCrypto.isValidPIN(pin) == valid)
    }
}

@Suite("Vault lifecycle")
@MainActor
struct VaultLifecycleTests {
    private func makeVault() -> (Vault, LibraryPaths) {
        let paths = LibraryPaths.temporary()
        return (Vault(paths: paths), paths)
    }

    @Test("A fresh library has no vault configured")
    func startsUnconfigured() {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        #expect(vault.state == .notConfigured)
        #expect(vault.currentKey == nil)
    }

    @Test("Setting a PIN configures and unlocks the vault")
    func setUpUnlocks() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("482913")
        #expect(vault.state == .unlocked)
        #expect(vault.currentKey != nil)
    }

    @Test("Locking discards the key; unlocking restores the same one")
    func lockThenUnlock() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("482913")
        let before = vault.currentKey

        vault.lock()
        #expect(vault.state == .locked)
        #expect(vault.currentKey == nil)

        try vault.unlock(pin: "482913")
        #expect(vault.state == .unlocked)
        #expect(vault.currentKey == before)
    }

    @Test("Content sealed before a lock is still readable after unlocking")
    func contentSurvivesLockCycle() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("482913")
        let id = UUID()
        let sealed = try vault.currentKey!.seal("IBAN NL91 ABNA 0417 1643 00", itemID: id)

        vault.lock()
        try vault.unlock(pin: "482913")
        #expect(try vault.currentKey!.openText(sealed, itemID: id) == "IBAN NL91 ABNA 0417 1643 00")
    }

    @Test("Changing the PIN preserves the data, and the old PIN stops working")
    func changePINPreservesData() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("1111")
        let id = UUID()
        let sealed = try vault.currentKey!.seal("client list", itemID: id)

        try vault.changePIN(current: "1111", new: "999999")
        #expect(try vault.currentKey!.openText(sealed, itemID: id) == "client list")

        vault.lock()
        #expect(throws: VaultError.wrongPIN) { try vault.unlock(pin: "1111") }
        try vault.unlock(pin: "999999")
        #expect(try vault.currentKey!.openText(sealed, itemID: id) == "client list")
    }

    @Test("A short PIN is refused")
    func shortPINRefused() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        #expect(throws: VaultError.pinTooShort) { try vault.setUpPIN("12") }
        #expect(vault.state == .notConfigured)
    }

    @Test("Five wrong PINs trigger a cooldown")
    func throttleAfterFiveFailures() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("482913")
        vault.lock()

        for _ in 0..<5 {
            #expect(throws: VaultError.wrongPIN) { try vault.unlock(pin: "000000") }
        }
        #expect(vault.failedAttempts >= 5)
        #expect(vault.throttledUntil != nil)

        // Even the correct PIN is refused while throttled.
        #expect(throws: (any Error).self) { try vault.unlock(pin: "482913") }
    }

    @Test("The vault reloads its configured state from disk")
    func statePersists() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let first = Vault(paths: paths)
        try first.setUpPIN("482913")

        let second = Vault(paths: paths)
        #expect(second.state == .locked)
        try second.unlock(pin: "482913")
        #expect(second.currentKey == first.currentKey)
    }

    @Test("Auto-lock fires only after the idle interval has elapsed")
    func autoLock() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("482913")
        vault.autoLockMinutes = 5

        #expect(vault.lockIfIdle(now: Date().addingTimeInterval(60)) == false)
        #expect(vault.state == .unlocked)

        #expect(vault.lockIfIdle(now: Date().addingTimeInterval(5 * 60 + 1)) == true)
        #expect(vault.state == .locked)
    }

    @Test("Auto-lock set to zero never fires")
    func autoLockDisabled() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("482913")
        vault.autoLockMinutes = 0
        #expect(vault.lockIfIdle(now: Date().addingTimeInterval(86_400)) == false)
        #expect(vault.state == .unlocked)
    }
}
