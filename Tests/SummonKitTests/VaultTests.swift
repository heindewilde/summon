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
        let wrapper = try VaultCrypto.wrap(master: master, secret: "4829", iterations: iters)
        let recovered = try VaultCrypto.unwrap(wrapper, secret: "4829")
        #expect(recovered == master)
    }

    @Test("A wrong PIN is rejected, not silently mis-decrypted")
    func wrongPINRejected() throws {
        let wrapper = try VaultCrypto.wrap(master: .generate(), secret: "1234", iterations: iters)
        #expect(throws: VaultError.wrongPIN) {
            _ = try VaultCrypto.unwrap(wrapper, secret: "1235")
        }
    }

    @Test("Each wrap uses a fresh salt, so the same PIN yields different ciphertext")
    func saltsAreUnique() throws {
        let master = VaultKey.generate()
        let a = try VaultCrypto.wrap(master: master, secret: "1234", iterations: iters)
        let b = try VaultCrypto.wrap(master: master, secret: "1234", iterations: iters)
        #expect(a.salt != b.salt)
        #expect(a.sealedMaster != b.sealedMaster)
        let ua = try VaultCrypto.unwrap(a, secret: "1234")
        let ub = try VaultCrypto.unwrap(b, secret: "1234")
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

    @Test("PIN policy accepts exactly four digits and nothing else",
          arguments: [("1234", true), ("0000", true), ("123", false),
                      ("12345", false), ("482913", false), ("12a4", false), ("", false)])
    func pinPolicy(pin: String, valid: Bool) {
        #expect(VaultSecretPolicy.isValid(pin, kind: .pin) == valid)
    }

    @Test("Passphrase policy holds the minimum length",
          arguments: [("correct horse battery", true), ("twelvechars!", true),
                      ("short", false), ("elevenchar", false), ("", false)])
    func passphrasePolicy(passphrase: String, valid: Bool) {
        #expect(VaultSecretPolicy.isValid(passphrase, kind: .passphrase) == valid)
    }

    @Test("A four-digit PIN is not accepted as a passphrase, and vice versa")
    func policiesDoNotOverlap() {
        #expect(!VaultSecretPolicy.isValid("4829", kind: .passphrase))
        #expect(!VaultSecretPolicy.isValid("correct horse battery", kind: .pin))
    }

    @Test("The wrapper records which kind of secret opens it")
    func wrapperCarriesKind() throws {
        let pinned = try VaultCrypto.wrap(master: .generate(), secret: "4829",
                                          kind: .pin, iterations: iters)
        let phrased = try VaultCrypto.wrap(master: .generate(), secret: "correct horse battery",
                                           kind: .passphrase, iterations: iters)
        #expect(pinned.kind == .pin)
        #expect(phrased.kind == .passphrase)
    }

    /// The compatibility case that matters: every vault written before passphrases
    /// existed has no `kindRaw` at all, and has to keep opening as a PIN.
    @Test("A wrapper written before passphrases existed still decodes, as a PIN")
    func legacyWrapperDecodesAsPIN() throws {
        let wrapper = try VaultCrypto.wrap(master: .generate(), secret: "4829",
                                           kind: .pin, iterations: iters)
        var fields = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrapper))
                as? [String: Any]
        )
        fields.removeValue(forKey: "kindRaw")
        let legacy = try JSONDecoder().decode(
            VaultWrapper.self,
            from: try JSONSerialization.data(withJSONObject: fields)
        )
        #expect(legacy.kind == .pin)
        #expect(legacy.sealedMaster == wrapper.sealedMaster)
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
        try vault.setUpPIN("4829")
        #expect(vault.state == .unlocked)
        #expect(vault.currentKey != nil)
    }

    @Test("Locking discards the key; unlocking restores the same one")
    func lockThenUnlock() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("4829")
        let before = vault.currentKey

        vault.lock()
        #expect(vault.state == .locked)
        #expect(vault.currentKey == nil)

        try vault.unlock(pin: "4829")
        #expect(vault.state == .unlocked)
        #expect(vault.currentKey == before)
    }

    @Test("Content sealed before a lock is still readable after unlocking")
    func contentSurvivesLockCycle() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("4829")
        let id = UUID()
        let sealed = try vault.currentKey!.seal("IBAN NL91 ABNA 0417 1643 00", itemID: id)

        vault.lock()
        try vault.unlock(pin: "4829")
        #expect(try vault.currentKey!.openText(sealed, itemID: id) == "IBAN NL91 ABNA 0417 1643 00")
    }

    @Test("Changing the PIN preserves the data, and the old PIN stops working")
    func changePINPreservesData() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("1111")
        let id = UUID()
        let sealed = try vault.currentKey!.seal("client list", itemID: id)

        try vault.changePIN(current: "1111", new: "9999")
        #expect(try vault.currentKey!.openText(sealed, itemID: id) == "client list")

        vault.lock()
        #expect(throws: VaultError.wrongPIN) { try vault.unlock(pin: "1111") }
        try vault.unlock(pin: "9999")
        #expect(try vault.currentKey!.openText(sealed, itemID: id) == "client list")
    }

    @Test("A short PIN is refused")
    func shortPINRefused() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        #expect(throws: VaultError.pinNotFourDigits) { try vault.setUpPIN("12") }
        #expect(vault.state == .notConfigured)
    }

    @Test("Five wrong PINs trigger a cooldown")
    func throttleAfterFiveFailures() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("4829")
        vault.lock()

        for _ in 0..<5 {
            #expect(throws: VaultError.wrongPIN) { try vault.unlock(pin: "000000") }
        }
        #expect(vault.failedAttempts >= 5)
        #expect(vault.throttledUntil != nil)

        // Even the correct PIN is refused while throttled.
        #expect(throws: (any Error).self) { try vault.unlock(pin: "4829") }
    }

    @Test("The vault reloads its configured state from disk")
    func statePersists() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let first = Vault(paths: paths)
        try first.setUpPIN("4829")

        let second = Vault(paths: paths)
        #expect(second.state == .locked)
        try second.unlock(pin: "4829")
        #expect(second.currentKey == first.currentKey)
    }

    @Test("Auto-lock fires only after the idle interval has elapsed")
    func autoLock() throws {
        let (vault, paths) = makeVault()
        defer { paths.destroy() }
        try vault.setUpPIN("4829")
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
        try vault.setUpPIN("4829")
        vault.autoLockMinutes = 0
        #expect(vault.lockIfIdle(now: Date().addingTimeInterval(86_400)) == false)
        #expect(vault.state == .unlocked)
    }

    @Test("Turning off the PIN decrypts everything first")
    func removingProtectionDecrypts() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")

        let secrets = store.createFolder(name: "Secrets")
        try store.setFolderSensitive(secrets, true)
        let inFolder = store.createSnippet(title: "Bank", body: "IBAN NL00", folder: secrets)
        let loose = store.createSnippet(title: "Passport", body: "NL123456")
        try store.setSensitive(loose, true)
        #expect(inFolder.sealedBody != nil)
        #expect(loose.sealedBody != nil)

        let decrypted = try store.clearAllSensitivity()
        #expect(decrypted == 2)
        // Readable on disk again — this is the step that has to happen before the key
        // is thrown away, or the content is unreadable forever.
        #expect(inFolder.bodyText == "IBAN NL00")
        #expect(loose.bodyText == "NL123456")
        #expect(!secrets.isSensitive)
        #expect(!loose.isSensitive)

        try vault.removePIN()
        #expect(!vault.isConfigured)
        // And still readable with no vault at all.
        store.refresh()
        #expect(store.snapshots.first { $0.id == loose.id }?.isLocked == false)
        #expect(store.snapshots.first { $0.id == loose.id }?.searchableText.contains("NL123456") == true)
    }

    @Test("Turning off the PIN needs the vault open")
    func removingProtectionNeedsUnlock() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")
        let item = store.createSnippet(title: "Bank", body: "IBAN NL00")
        try store.setSensitive(item, true)

        vault.lock()
        // Refusing is the whole point: decrypting is impossible without the key, and
        // going ahead anyway would strand the content.
        #expect(throws: VaultError.locked) { _ = try store.clearAllSensitivity() }
    }

    @Test("Changing the PIN re-keys rather than re-encrypting")
    func changingPINKeepsContentSealed() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")
        let item = store.createSnippet(title: "Bank", body: "IBAN NL00")
        try store.setSensitive(item, true)
        let sealedBefore = item.sealedBody

        try vault.changePIN(current: "1379", new: "2468")
        // The master key is unwrapped and re-wrapped; the content itself is untouched.
        #expect(item.sealedBody == sealedBefore)

        vault.lock()
        #expect(throws: VaultError.wrongPIN) { try vault.unlock(pin: "1379") }
        try vault.unlock(pin: "2468")
        store.refresh()
        #expect(store.snapshots.first { $0.id == item.id }?.searchableText.contains("IBAN") == true)
    }
}

@Suite("Sealed summaries")
@MainActor
struct SealedSummaryTests {

    /// The summary is the content's own first sentence when the model is unavailable
    /// or refuses to look — which for a sensitive item is always. It has to be sealed.
    @Test("A sensitive item's summary never sits in the clear")
    func summaryIsSealedForSensitiveItems() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")

        let secret = "Passport number NLD1234567, issued in Amsterdam."
        let item = store.createSnippet(title: "Passport", body: secret, sensitive: true)
        store.applySummary(item, Heuristics.summary(forText: secret))

        #expect(item.summary == nil)
        #expect(item.sealedSummary != nil)
        #expect(store.resolveSummary(item, key: vault.currentKey)?.contains("NLD1234567") == true)
        // And nothing at all once the key is gone.
        #expect(store.resolveSummary(item, key: nil) == nil)
    }

    @Test("Marking an existing item sensitive seals the summary it already had")
    func markingSensitiveSealsAnExistingSummary() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")

        // This is the order that leaked: enriched while ordinary, sealed afterwards.
        let item = store.createSnippet(title: "Bank", body: "IBAN NL00 BANK 0123 4567 89")
        store.applySummary(item, "IBAN NL00 BANK 0123 4567 89")
        #expect(item.summary != nil)

        try store.setSensitive(item, true)
        #expect(item.summary == nil)
        #expect(item.sealedSummary != nil)

        // Reversible, like every other sealed field.
        try store.setSensitive(item, false)
        #expect(item.sealedSummary == nil)
        #expect(item.summary == "IBAN NL00 BANK 0123 4567 89")
    }

    @Test("A locked item's snapshot carries no summary")
    func lockedSnapshotHasNoSummary() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")

        let item = store.createSnippet(title: "Passport", body: "NLD1234567", sensitive: true)
        store.applySummary(item, "Passport number NLD1234567")
        store.save()

        vault.lock()
        store.refresh()
        let snapshot = try #require(store.snapshots.first { $0.id == item.id })
        #expect(snapshot.isLocked)
        #expect(snapshot.summary == nil)
        #expect(snapshot.title == "Passport")
    }
}

@Suite("Passphrase option")
@MainActor
struct PassphraseTests {
    private let phrase = "correct horse battery"

    @Test("A vault can be set up with a passphrase instead of a PIN")
    func setUpWithPassphrase() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)

        try vault.setUpSecret(phrase, kind: .passphrase)
        #expect(vault.secretKind == .passphrase)
        #expect(vault.isUnlocked)

        vault.lock()
        #expect(throws: VaultError.wrongPIN) { try vault.unlock(secret: "4829") }
        try vault.unlock(secret: phrase)
        #expect(vault.isUnlocked)
    }

    @Test("Each kind holds its own length rule at setup")
    func setupEnforcesTheRightPolicy() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)

        #expect(throws: VaultError.passphraseTooShort) {
            try vault.setUpSecret("tooshort", kind: .passphrase)
        }
        #expect(throws: VaultError.pinNotFourDigits) {
            try vault.setUpSecret(phrase, kind: .pin)
        }
        #expect(!vault.isConfigured)
    }

    /// The point of the switch being a re-wrap: content is sealed under the master
    /// key, which never changes, so nothing has to be decrypted and rewritten.
    @Test("Switching from a PIN to a passphrase leaves content sealed and readable")
    func switchingKindKeepsContent() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("4829")

        let item = store.createSnippet(title: "Passport", body: "NLD1234567", sensitive: true)
        let sealedBefore = item.sealedBody
        #expect(sealedBefore != nil)

        try vault.changeSecret(current: "4829", new: phrase, kind: .passphrase)
        #expect(vault.secretKind == .passphrase)
        // The very same ciphertext — this was a re-wrap, not a re-encrypt.
        #expect(item.sealedBody == sealedBefore)

        vault.lock()
        try vault.unlock(secret: phrase)
        #expect(store.resolveBodyText(item, key: vault.currentKey) == "NLD1234567")
    }

    @Test("Switching back to a PIN works the same way")
    func switchingBackToPIN() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        try vault.setUpSecret(phrase, kind: .passphrase)

        try vault.changeSecret(current: phrase, new: "1379", kind: .pin)
        #expect(vault.secretKind == .pin)
        vault.lock()
        try vault.unlock(secret: "1379")
        #expect(vault.isUnlocked)
    }

    @Test("A wrong current secret cannot re-key the vault")
    func changeNeedsTheCurrentSecret() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        try vault.setUpPIN("4829")

        #expect(throws: VaultError.wrongPIN) {
            try vault.changeSecret(current: "0000", new: phrase, kind: .passphrase)
        }
        #expect(vault.secretKind == .pin)
    }

    /// `changeSecret` used to unwrap directly, with no counter and no cooldown, which
    /// made "change my PIN" an unthrottled oracle for the current one.
    @Test("Changing the secret is throttled like any other guess")
    func changeIsThrottled() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        try vault.setUpPIN("4829")

        for _ in 0..<5 {
            #expect(throws: VaultError.wrongPIN) {
                try vault.changeSecret(current: "0000", new: "1111", kind: .pin)
            }
        }
        #expect(vault.failedAttempts == 5)
        #expect(vault.throttledUntil != nil)

        // And the cooldown applies to the change path, not only to unlocking.
        #expect(throws: (any Error).self) {
            try vault.changeSecret(current: "4829", new: "1111", kind: .pin)
        }
    }

    @Test("Changing without naming a kind keeps the one already in use")
    func changeKeepsKindByDefault() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        try vault.setUpSecret(phrase, kind: .passphrase)

        try vault.changeSecret(current: phrase, new: "a longer passphrase")
        #expect(vault.secretKind == .passphrase)
    }
}

@Suite("Sealing leaves nothing behind")
@MainActor
struct SealResidueTests {

    /// The transition is the dangerous moment: the item was legitimately plaintext,
    /// and SQLite does not zero the pages it frees when that plaintext is nilled.
    @Test("Plaintext is gone from the store file after an item is sealed")
    func sealingScrubsTheStoreFile() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")

        // Distinctive enough that finding it in the file cannot be a coincidence.
        let secret = "ZmarkerQ Passport NLD1234567 ZmarkerQ"
        let item = store.createSnippet(title: "Passport", body: secret)
        store.save()

        // Present while it is an ordinary item — otherwise the test proves nothing.
        #expect(try fileContains(paths.storeURL, secret))

        try store.setSensitive(item, true)
        #expect(item.sealedBody != nil)
        #expect(item.bodyText == nil)
        #expect(try !fileContains(paths.storeURL, secret))
    }

    @Test("Turning protection off and on again leaves no earlier copy")
    func repeatedTransitionsScrub() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        try vault.setUpPIN("1379")

        let secret = "ZmarkerR IBAN NL00 BANK 0123 ZmarkerR"
        let item = store.createSnippet(title: "Bank", body: secret, sensitive: true)
        store.save()
        #expect(try !fileContains(paths.storeURL, secret))

        // Decrypted back to plaintext on purpose, then sealed again.
        _ = try store.clearAllSensitivity()
        #expect(try fileContains(paths.storeURL, secret))

        try vault.setUpPIN("1379")
        try store.setSensitive(item, true)
        #expect(try !fileContains(paths.storeURL, secret))
    }

    /// Scans the store and both its SQLite sidecars for the bytes.
    ///
    /// The WAL matters as much as the main file: a fresh write lands in
    /// `Library.store-wal` first, so checking only `Library.store` would report a
    /// scrub that had not happened and pass whatever we did.
    private func fileContains(_ storeURL: URL, _ needle: String) throws -> Bool {
        let bytes = Data(needle.utf8)
        guard !bytes.isEmpty else { return false }
        for path in [storeURL.path, storeURL.path + "-wal", storeURL.path + "-shm"] {
            guard let haystack = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            if haystack.range(of: bytes) != nil { return true }
        }
        return false
    }
}

@Suite("Cooldown and wrapper bounds")
@MainActor
struct CooldownTests {

    private func wrapper(failures: Int, lastFailedAt: Date?) throws -> VaultWrapper {
        var w = try VaultCrypto.wrap(master: .generate(), secret: "4829",
                                     kind: .pin, iterations: 1_000)
        w.failedAttempts = failures
        w.lastFailedAt = lastFailedAt
        return w
    }

    @Test("Under the threshold there is no cooldown at all",
          arguments: [0, 1, 4])
    func noCooldownEarly(failures: Int) throws {
        let w = try wrapper(failures: failures, lastFailedAt: Date())
        #expect(Vault.remainingCooldown(w) == nil)
    }

    @Test("The cooldown escalates and caps at five minutes")
    func cooldownEscalates() {
        #expect(Vault.cooldown(afterFailures: 4) == 0)
        #expect(Vault.cooldown(afterFailures: 5) == 30)
        #expect(Vault.cooldown(afterFailures: 6) == 60)
        #expect(Vault.cooldown(afterFailures: 7) == 120)
        #expect(Vault.cooldown(afterFailures: 20) == 300)
    }

    @Test("Waiting it out clears it")
    func expiresOnItsOwn() throws {
        let w = try wrapper(failures: 5, lastFailedAt: Date())
        let later = Date().addingTimeInterval(31)
        #expect(Vault.remainingCooldown(w, now: later) == nil)
    }

    /// The bug: `lockedUntil` was an absolute deadline, so moving the system clock
    /// back past it cleared the cooldown. Elapsed time cannot be gamed that way.
    @Test("Setting the clock back does not clear the cooldown")
    func clockRollbackDoesNotHelp() throws {
        let w = try wrapper(failures: 5, lastFailedAt: Date())
        let yesterday = Date().addingTimeInterval(-86_400)
        let remaining = try #require(Vault.remainingCooldown(w, now: yesterday))
        // Negative elapsed time reads as none passed, so the full wait is still owed.
        #expect(remaining == 30)
    }

    @Test("An absurd iteration count is clamped rather than hung on")
    func iterationsAreClamped() throws {
        var w = try wrapper(failures: 0, lastFailedAt: nil)
        w.iterations = .max
        #expect(w.safeIterations == VaultWrapper.maximumIterations)

        w.iterations = 0
        #expect(w.safeIterations == VaultWrapper.minimumIterations)

        w.iterations = 600_000
        #expect(w.safeIterations == 600_000)
    }
}

@Suite("Scratch files")
struct ScratchFileTests {

    @Test("A stored name cannot put a decrypted copy outside the scratch directory",
          arguments: ["../../evil.txt", "../evil.txt", "/etc/evil.txt",
                      "..", ".", "", "a/b/c.txt"])
    func scratchNameIsContained(originalName: String) {
        let id = UUID()
        let blob = StoredBlob(filename: "\(id).enc", byteSize: 1, contentHash: "",
                              isSealed: true, fileExtension: "txt",
                              originalName: originalName)
        let name = FileStore.scratchName(for: blob, itemID: id)
        #expect(!name.contains("/"))
        #expect(name != "..")
        #expect(name != ".")
        #expect(!name.isEmpty)
    }

    @Test("An ordinary name is kept, so the file opens as itself elsewhere")
    func ordinaryNameSurvives() {
        let id = UUID()
        let blob = StoredBlob(filename: "\(id).enc", byteSize: 1, contentHash: "",
                              isSealed: true, fileExtension: "pdf",
                              originalName: "Portfolio 2026.pdf")
        #expect(FileStore.scratchName(for: blob, itemID: id) == "Portfolio 2026.pdf")
    }

    @Test("A decrypted copy is readable only by its owner")
    func materialisedFileIsPrivate() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy(); FileStore.clearScratch() }
        let store = FileStore(paths: paths)
        let key = VaultKey.generate()
        let id = UUID()

        let blob = try store.importData(Data("passport scan".utf8), itemID: id,
                                        fileExtension: "txt", originalName: "scan.txt",
                                        key: key)
        let url = try store.materialize(blob, itemID: id, key: key)

        let mode = try #require(
            try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        #expect(mode.int16Value == 0o600)
        #expect(try Data(contentsOf: url) == Data("passport scan".utf8))
    }

    @Test("A file above the import ceiling is refused rather than loaded")
    func oversizedImportIsRefused() throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let store = FileStore(paths: paths)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "huge-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        // Sparse, so the test costs no real disk: the size check reads metadata.
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(FileStore.maximumImportBytes + 1))
        try handle.close()

        #expect(throws: FileStoreError.self) {
            _ = try store.importFile(at: url, itemID: UUID(), key: nil)
        }
    }
}

@Suite("Repairing an older library")
@MainActor
struct ScrubMigrationTests {

    private func makeLibrary() throws -> (LibraryStore, Vault, LibraryPaths) {
        let paths = LibraryPaths.temporary()
        let vault = Vault(paths: paths)
        let store = try LibraryStore(paths: paths, vault: vault)
        return (store, vault, paths)
    }

    /// Reproduces what an older version left behind: an item that is sensitive, and
    /// whose summary was written straight onto the model in the clear.
    @Test("A plaintext summary on a sensitive item is sealed")
    func sealsLeftoverSummaries() throws {
        let (store, vault, paths) = try makeLibrary()
        defer { paths.destroy() }
        try vault.setUpPIN("1379")

        let item = store.createSnippet(title: "Passport", body: "NLD1234567", sensitive: true)
        // Written the way the old code did, bypassing `applySummary`.
        item.summary = "Passport number NLD1234567"
        item.sealedSummary = nil
        store.save()

        #expect(store.scrubSensitiveContent() == 1)
        #expect(item.summary == nil)
        #expect(item.sealedSummary != nil)
        #expect(store.resolveSummary(item, key: vault.currentKey) == "Passport number NLD1234567")
    }

    /// The other half of the silent-failure bug: marked sensitive, never sealed.
    @Test("Content a swallowed failure left in the clear is sealed")
    func sealsUnsealedContent() throws {
        let (store, vault, paths) = try makeLibrary()
        defer { paths.destroy() }
        try vault.setUpPIN("1379")

        let item = store.createSnippet(title: "Bank", body: "IBAN NL00 BANK 0123")
        // Marked sensitive with its bytes never following, which is exactly what the
        // old `try?` produced when a seal failed.
        item.isSensitive = true
        store.save()
        #expect(item.bodyText != nil)

        #expect(store.scrubSensitiveContent() == 1)
        #expect(item.bodyText == nil)
        #expect(item.sealedBody != nil)
        #expect(store.resolveBodyText(item, key: vault.currentKey) == "IBAN NL00 BANK 0123")
    }

    @Test("It runs once, then leaves the library alone")
    func runsOnce() throws {
        let (store, vault, paths) = try makeLibrary()
        defer { paths.destroy() }
        try vault.setUpPIN("1379")

        let item = store.createSnippet(title: "Passport", body: "NLD1234567", sensitive: true)
        item.summary = "leftover"
        store.save()

        #expect(store.scrubSensitiveContent() == 1)
        // A second call must not repeat the work, or every unlock would vacuum.
        #expect(store.scrubSensitiveContent() == 0)
        #expect(FileManager.default.fileExists(atPath: paths.migrationsFile.path))
    }

    @Test("Without the key it changes nothing and stays pending")
    func needsTheKey() throws {
        let (store, vault, paths) = try makeLibrary()
        defer { paths.destroy() }
        try vault.setUpPIN("1379")
        let item = store.createSnippet(title: "Passport", body: "NLD1234567", sensitive: true)
        item.summary = "leftover"
        store.save()

        vault.lock()
        #expect(store.scrubSensitiveContent() == 0)
        #expect(item.summary == "leftover")

        // And still runs once the vault is open, rather than having marked itself done.
        try vault.unlock(pin: "1379")
        #expect(store.scrubSensitiveContent() == 1)
    }

    @Test("An ordinary item is left exactly as it is")
    func leavesOrdinaryItemsAlone() throws {
        let (store, vault, paths) = try makeLibrary()
        defer { paths.destroy() }
        try vault.setUpPIN("1379")

        let item = store.createSnippet(title: "Terms", body: "Payment in 30 days")
        item.summary = "Standard payment terms"
        store.save()

        #expect(store.scrubSensitiveContent() == 0)
        #expect(item.summary == "Standard payment terms")
        #expect(item.bodyText == "Payment in 30 days")
    }

    /// The residue is from seals that happened before this code existed, so the
    /// vacuum has to happen whether or not the pass found anything to re-seal.
    @Test("The one-time pass vacuums even when nothing needed re-sealing")
    func vacuumsRegardless() throws {
        let (store, vault, paths) = try makeLibrary()
        defer { paths.destroy() }
        try vault.setUpPIN("1379")

        let residue = "ZmarkerS old plaintext ZmarkerS"
        let item = store.createSnippet(title: "Old", body: residue)
        store.save()
        // Sealed the way the current code does, but with the vacuum skipped, which is
        // the state every library upgraded from an earlier version is in.
        item.sealedBody = try #require(try vault.currentKey?.seal(residue, itemID: item.id))
        item.bodyText = nil
        item.isSensitive = true
        store.save()

        let storeURL = paths.storeURL
        func residuePresent() -> Bool {
            for path in [storeURL.path, storeURL.path + "-wal"] {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
                if data.range(of: Data(residue.utf8)) != nil { return true }
            }
            return false
        }
        #expect(residuePresent())

        #expect(store.scrubSensitiveContent() == 0)
        #expect(!residuePresent())
    }
}
