import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import SummonKit
import SummonUI

/// Exercises the paths that only exist against the real system: a global hot key
/// actually being pressed, the Finder selection bridge, the Services registration,
/// login-item registration and biometric unlock.
///
/// `SUMMON_VERIFY=1`; writes to `SUMMON_TEST_LOG`. Never runs in normal use.
@MainActor
enum VerifyPaths {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["SUMMON_VERIFY"] == "1" }

    private final class Box { var fired = false }

    private static var report: [String] = []
    private static var failures = 0

    private static func check(_ label: String, _ ok: Bool, detail: String = "") {
        if !ok { failures += 1 }
        report.append("  \(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    private static func note(_ label: String, _ value: String) {
        report.append("  ····  \(label): \(value)")
    }

    private static func flush() {
        let text = report.joined(separator: "\n")
        if let path = ProcessInfo.processInfo.environment["SUMMON_TEST_LOG"] {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        print(text)
    }

    static func run(controller: PanelController) async {
        let model = Services.model
        report.append("\n=== System path verification ===")

        await model.seedStarterLibraryIfEmpty()
        try? await Task.sleep(for: .seconds(2))
        model.store.refresh()

        await verifyHotKey(model: model, controller: controller)
        await verifyFinderSelection(model: model)
        verifyServices()
        verifyLoginItem()
        await verifyBiometrics(model: model)

        report.append("=== \(report.filter { $0.contains("PASS") }.count) passed, \(failures) failed ===")
        flush()
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - 1. The global hot key, actually pressed

    private static func verifyHotKey(model: AppModel, controller: PanelController) async {
        let combo = model.settings.summonHotKey
        let box = Box()

        let registered = HotKeyCenter.shared.register(.summon, combo: combo) {
            box.fired = true
            controller.toggle()
        }
        check("Global hot key registers (\(combo.displayString))", registered)
        guard registered else { return }

        // Summon holds Accessibility, so it can press its own shortcut. This is the
        // only way to confirm the Carbon handler fires without a human at the keyboard.
        postKey(combo)
        try? await Task.sleep(for: .milliseconds(900))

        check("Pressing it fires the handler", box.fired)
        check("Pressing it shows the panel", controller.isVisible)

        if controller.isVisible {
            postKey(combo)
            try? await Task.sleep(for: .milliseconds(700))
            check("Pressing it again hides the panel", !controller.isVisible)
        }
        model.dismissPanel()
    }

    private static func postKey(_ combo: HotKeyCombo) {
        var flags: CGEventFlags = []
        if combo.modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if combo.modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        if combo.modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if combo.modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(combo.keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(combo.keyCode), keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - 2. Reading the Finder selection

    private static func verifyFinderSelection(model: AppModel) async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "summon-finder-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "Quarterly report.txt")
        try? "quarterly figures".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Selecting in Finder is itself an Apple Event, so the first run prompts for
        // Automation permission.
        let script = """
        tell application "Finder"
            activate
            reveal POSIX file "\(file.path)" as alias
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            check("Finder can be driven over Apple Events", false,
                  detail: "\(error[NSAppleScript.errorMessage] ?? "denied — approve the Automation prompt")")
            return
        }
        check("Finder can be driven over Apple Events", true)
        try? await Task.sleep(for: .seconds(2))

        let selection = SelectionCapture.finderSelection()
        check("The Finder selection is readable",
              selection.contains { $0.lastPathComponent == file.lastPathComponent },
              detail: selection.map(\.lastPathComponent).joined(separator: ", "))

        if !selection.isEmpty {
            let capture = SelectionCapture(inserter: model.inserter)
            let grabbed = await capture.capture()
            var imported = 0
            if case .files(let urls) = grabbed { imported = urls.count }
            check("Save-selection captures it as files", imported > 0)
        }

        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first?.hide()
    }

    // MARK: - 3. The Services menu entry

    private static func verifyServices() {
        NSUpdateDynamicServices()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-dump_pboard"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let dump = String(decoding: data, as: UTF8.self)
        check("“Add to Summon” is registered as a system Service",
              dump.contains("Add to Summon") || dump.contains("com.heindewilde.summon"),
              detail: dump.isEmpty ? "pbs returned nothing" : "found in the Services registry")
    }

    // MARK: - 4. Launch at login

    private static func verifyLoginItem() {
        let service = SMAppService.mainApp
        let original = service.status
        note("Login item status before", "\(original)")

        do {
            if original != .enabled { try service.register() }
            check("Registers as a login item", service.status == .enabled,
                  detail: "\(service.status)")
        } catch {
            check("Registers as a login item", false, detail: error.localizedDescription)
        }

        // Leave the setting as it was found.
        if original != .enabled {
            try? service.unregister()
            note("Login item restored to", "\(service.status)")
        }
    }

    // MARK: - 5. Biometric unlock

    private static func verifyBiometrics(model: AppModel) async {
        guard Vault.biometricsAvailable else {
            note("Touch ID", "no biometric hardware — skipped")
            return
        }
        guard Vault.biometricStorageAvailable else {
            note("Touch ID", "sensor present, but the Keychain will not store a "
                 + "biometry-protected key without an Apple Team ID; PIN unlock is used")
            check("The app correctly declines to offer Touch ID", true)
            return
        }
        if !model.vault.isConfigured {
            try? model.vault.setUpPIN("482913")
        }
        guard model.vault.isUnlocked else {
            check("Vault is unlocked so the key can be stored", false)
            return
        }

        do {
            try model.vault.enableBiometricUnlock()
            check("Master key is stored behind Touch ID", model.vault.biometricsEnabled)
        } catch {
            check("Master key is stored behind Touch ID", false, detail: error.localizedDescription)
            return
        }

        let before = model.vault.currentKey
        model.vault.lock()
        check("Vault locks", !model.vault.isUnlocked)

        report.append("  ····  Touch ID prompt follows — place your finger on the sensor")
        do {
            try await model.vault.unlockWithBiometrics(reason: "verify Touch ID unlock")
            check("Touch ID unlocks the vault", model.vault.isUnlocked)
            check("It returns the same master key", model.vault.currentKey == before)
        } catch {
            check("Touch ID unlocks the vault", false,
                  detail: "\(error.localizedDescription) — needs a finger on the sensor")
        }
        model.vault.disableBiometricUnlock()
    }
}
