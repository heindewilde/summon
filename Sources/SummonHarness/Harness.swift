import AppKit
import Foundation
import SummonKit
import SummonMacApp

/// The runtime harnesses, and the one rule all of them share.
///
/// Every mode here drives the real app rather than a test double, and several of them
/// are destructive: `SelfTest` sets up a vault, marks items sensitive and then calls
/// `removeVaultProtection`, which decrypts everything and deletes the key file.
/// `VerifyPaths` sets a PIN of its own. `UIProbe` posts synthetic keystrokes into
/// whatever holds focus. None of that may ever touch a real library.
///
/// `Scripts/selftest.sh` has always set `SUMMON_DEMO=1`, but the app never insisted,
/// so `SUMMON_SELFTEST=1 open dist/Summon.app` ran the whole self-test against the
/// real library — and turned that library's encryption off on the way through. This
/// refuses instead.
///
/// Not `#if DEBUG`, deliberately. The performance budgets only assert anything in a
/// release build, so `selftest.sh` runs the release binary on purpose; compiling the
/// harness out of release would mean the checks could only ever run against a build
/// nobody ships. Gating on the demo library keeps both properties.
@MainActor
enum Harness {
    /// Every variable that puts the app into a harness mode rather than normal use.
    ///
    /// `SUMMON_DEMO` and `SUMMON_APPEARANCE` are absent on purpose: they redirect the
    /// library and force an appearance, which is not a mode — it is the thing that
    /// makes a mode safe, and a preference.
    static let triggers = [
        "SUMMON_SELFTEST",
        "SUMMON_UIPROBE",
        "SUMMON_DRAGPROBE",
        "SUMMON_VERIFY",
        "SUMMON_PASTETEST",
        "SUMMON_LIVE",
        "SUMMON_SNAPSHOT",
    ]

    static var requested: [String] {
        let environment = ProcessInfo.processInfo.environment
        return triggers.filter { environment[$0] != nil }
    }

    /// Nil when the app may carry on; a message to print and die on when it may not.
    static var refusal: String? {
        let asked = requested
        guard !asked.isEmpty, !LibraryPaths.isDemoMode else { return nil }
        return """
        Summon: refusing to run \(asked.joined(separator: ", ")) against a real library.

        These modes edit the library they are pointed at — the self-test decrypts
        every sensitive item and removes the vault key — so they only run against the
        throwaway demo library.

        Re-run with SUMMON_DEMO=1, or use Scripts/selftest.sh, which sets it for you.
        """
    }

    /// Prints the refusal and exits. Called before any mode is dispatched.
    static func refuseIfPointedAtARealLibrary() {
        guard let refusal else { return }
        FileHandle.standardError.write(Data((refusal + "\n").utf8))
        exit(2)
    }
}

/// The dispatch `AppDelegate` used to carry inline, now behind `AppDelegate.harness`
/// so the shipped app does not link any of it.
public enum HarnessLauncher {
    /// Installs the dispatcher. Call before `SummonApp.main()`.
    @MainActor
    public static func install() {
        AppDelegate.harness = dispatch
    }

    /// True when a harness mode has taken over the launch.
    @MainActor
    static func dispatch(controller: PanelController) -> Bool {
        // Before any mode is dispatched: several of them are destructive, and the
        // demo library is the only one they are allowed to be destructive to.
        Harness.refuseIfPointedAtARealLibrary()

        if VerifyPaths.isRequested {
            Task { await VerifyPaths.run(controller: controller) }
            return true
        }
        if PasteTest.isRequested {
            Task { await PasteTest.run() }
            return true
        }
        if let live = LiveCapture.mode {
            Task { await LiveCapture.run(mode: live, controller: controller) }
            return true
        }
        if DragProbe.isRequested {
            Task { await DragProbe.run() }
            return true
        }
        if UIProbe.isRequested {
            Task { await UIProbe.run(controller: controller) }
            return true
        }
        if SelfTest.isRequested {
            Task { await SelfTest.run(controller: controller) }
            return true
        }
        if let directory = SnapshotRunner.requestedDirectory {
            Task { await SnapshotRunner.run(into: directory) }
            return true
        }
        return false
    }
}
