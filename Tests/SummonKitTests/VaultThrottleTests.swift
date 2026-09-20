import Foundation
import Testing
@testable import SummonKit

/// Where wrong guesses are recorded, which is not where the key is.
@Suite("Throttle stays on the device")
@MainActor
struct VaultThrottleTests {

    @Test("The wrapper file carries no attempt state at all")
    func wrapperHoldsNoThrottle() async throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        try await vault.setUpPIN("4829")

        // Three wrong guesses, recorded somewhere.
        for _ in 0..<3 { try? await vault.unlock(pin: "0000") }

        let onDisk = try String(contentsOf: paths.vaultKeyFile, encoding: .utf8)
        #expect(!onDisk.contains("lastFailedAt"),
                "the file that would sync must not carry when you last guessed wrong")
        #expect(onDisk.contains("\"failedAttempts\":0"),
                "and must not carry how many times")

        let throttle = try String(contentsOf: paths.vaultThrottleFile, encoding: .utf8)
        #expect(throttle.contains("failedAttempts"))
    }

    @Test("A cooldown survives a reload")
    func survivesReload() async throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        try await vault.setUpPIN("4829")
        for _ in 0..<6 { try? await vault.unlock(pin: "0000") }
        #expect(vault.throttledUntil != nil, "six wrong guesses must cost something")

        let reopened = Vault(paths: paths)
        #expect(reopened.throttledUntil != nil, "and it must not be forgiven by a relaunch")
    }

    /// Deleting the throttle file must not be a way to clear a cooldown that came
    /// from a wrapper written before the split.
    @Test("A pre-split wrapper keeps its cooldown")
    func legacyWrapperKeepsCooldown() async throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths)
        try await vault.setUpPIN("4829")
        for _ in 0..<6 { try? await vault.unlock(pin: "0000") }

        // The shape an older library is in: counters inline, no separate file.
        var wrapper = try #require(vault.wrapperForTesting)
        wrapper.failedAttempts = 6
        wrapper.lastFailedAt = Date()
        try JSONEncoder().encode(wrapper).write(to: paths.vaultKeyFile, options: .atomic)
        try FileManager.default.removeItem(at: paths.vaultThrottleFile)

        let reopened = Vault(paths: paths)
        #expect(reopened.throttledUntil != nil, "an upgrade must not forgive a pending cooldown")
    }
}

@Suite("The master key across devices")
@MainActor
struct SharedMasterKeyTests {
    /// Every vault a test builds sits on a temporary library, which is what turns
    /// iCloud Keychain off. Asserted here because the alternative is a test run that
    /// adopts the developer's real master key — or publishes a throwaway one to the
    /// account the machine is signed in to.
    @Test("A test vault never takes part in iCloud Keychain")
    func temporaryLibrariesDoNotSync() {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        #expect(paths.isInAppGroupContainer == false)
    }

    @Test("Setting a secret with no shared key generates a fresh one")
    func generatesWhenNothingToJoin() async throws {
        let paths = LibraryPaths.temporary()
        defer { paths.destroy() }
        let vault = Vault(paths: paths, syncsMasterKey: false)
        try await vault.setUpPIN("1234")
        #expect(vault.joinedExistingVault == false)
        #expect(vault.isUnlocked)
    }

    @Test("The device-local files sit outside the library")
    func deviceFilesAreSeparate() {
        let paths = LibraryPaths(
            root: URL(fileURLWithPath: "/tmp/group/Summon"),
            deviceRoot: URL(fileURLWithPath: "/tmp/device/Summon"))
        #expect(paths.vaultKeyFile.path.hasPrefix("/tmp/device"))
        #expect(paths.vaultThrottleFile.path.hasPrefix("/tmp/device"))
        #expect(paths.storeURL.path.hasPrefix("/tmp/group"))
    }
}
