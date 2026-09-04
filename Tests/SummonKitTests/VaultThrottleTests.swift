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
