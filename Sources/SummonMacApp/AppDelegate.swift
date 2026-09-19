import AppKit
import SwiftUI
import SummonKit
import SummonKitMac
import SummonUI
import SummonUIMac

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set before `SummonApp.main()` by a launcher that links `SummonHarness`.
    /// Returns true when a harness mode has taken over the launch.
    ///
    /// A hook rather than an import, so the harness stays out of the shipped app: it
    /// drives synthetic input, runs AppleScript and writes to `/tmp`, none of which
    /// belongs in a sandboxed App Store binary. It is not `#if DEBUG` either — the
    /// performance budgets only assert in release, and `Scripts/selftest.sh` runs the
    /// release build on purpose.
    public static var harness: (@MainActor (PanelController) -> Bool)?

    private(set) var panelController: PanelController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let model = Services.model
        let controller = PanelController(model: model)
        panelController = controller

        model.showPanelHandler = { [weak controller] in controller?.show() }
        model.hidePanelHandler = { [weak controller] in controller?.hide() }
        model.reregisterHotKeysHandler = { [weak self] in self?.registerHotKeys() }

        registerHotKeys()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        applyActivationPolicy()
        // Also hands the model its shortcut labels and applies the stored appearance.
        // Both have to happen here rather than at construction: `AppSettings` is built
        // before `NSApp` exists, so the stored choice has nobody to tell at that point.
        MacSettings.shared.bind(to: model)

        // Anything left in the scratch directory got there before this launch, which
        // means a crash or a force-quit took the exit paths away from it. Decrypted
        // copies of sealed files are exactly what should not outlive a session.
        FileStore.clearScratch()

        // A development launcher can take the launch over for a runtime harness. The
        // App Store build links no harness, so there this is always nil.
        if let harness = Self.harness, harness(controller) {
            return
        }

        // First run opens onboarding rather than dropping someone into an empty app
        // with an unexplained global shortcut.
        if !model.settings.hasCompletedOnboarding {
            model.showOnboardingHandler?()
        }

        // Deferred so it cannot slow launch: the panel is built and laid out while the
        // machine is idle rather than inline on the first ⌥Space.
        Task { @MainActor [weak controller] in
            try? await Task.sleep(for: .milliseconds(250))
            controller?.prewarm()
        }
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(Services.model.settings.showDockIcon ? .regular : .accessory)
    }

    func registerHotKeys() {
        let model = Services.model
        let center = HotKeyCenter.shared

        let summonOK = center.register(.summon, combo: MacSettings.shared.summonHotKey) { [weak self] in
            self?.panelController?.toggle()
        }
        if !summonOK {
            model.show(Toast(
                text: "\(MacSettings.shared.summonHotKey.displayString) is taken by another app",
                symbol: "keyboard.badge.exclamationmark",
                tone: .warning,
                detail: "Choose a different shortcut in Settings"
            ))
        }

        if model.settings.quickSaveEnabled {
            center.register(.quickSave, combo: MacSettings.shared.quickSaveHotKey) {
                Services.model.quickSaveSelection()
            }
        } else {
            center.unregister(.quickSave)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Summon lives in the menu bar; closing the library window is not quitting.
        false
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Services.model.showMainWindowHandler?() }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
        FileStore.clearScratch()
    }

    // MARK: - Services menu

    /// Backs the "Add to Summon" entry in every app's right-click Services menu.
    @objc func addToSummon(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let model = Services.model

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            model.importDroppedFiles(urls)
            return
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            Task { @MainActor in
                if let item = await model.importer.importImage(data) {
                    model.runSearch()
                    model.show(Toast(text: "Saved “\(item.title)”", symbol: "sparkles", tone: .success))
                }
            }
            return
        }
        if let text = pasteboard.string(forType: .string) {
            let rtf = pasteboard.data(forType: .rtf)
            Task { @MainActor in
                if let item = await model.importer.importText(text, rtf: rtf) {
                    model.runSearch()
                    model.show(Toast(text: "Saved “\(item.title)”", symbol: "sparkles", tone: .success))
                }
            }
            return
        }
        error.pointee = "Summon couldn’t read that selection." as NSString
    }
}
