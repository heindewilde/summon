import AppKit
import SwiftUI
import SummonKit
import SummonUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        // Applied here as well as from Settings: `AppSettings` is constructed before
        // `NSApp` exists, so the stored choice has nobody to tell at that point.
        model.settings.applyAppearance()

        // Anything left in the scratch directory got there before this launch, which
        // means a crash or a force-quit took the exit paths away from it. Decrypted
        // copies of sealed files are exactly what should not outlive a session.
        FileStore.clearScratch()

        // Before any harness mode is dispatched: several of them are destructive, and
        // the demo library is the only one they are allowed to be destructive to.
        Harness.refuseIfPointedAtARealLibrary()

        if VerifyPaths.isRequested {
            Task { await VerifyPaths.run(controller: controller) }
            return
        }

        if PasteTest.isRequested {
            Task { await PasteTest.run() }
            return
        }

        if let live = LiveCapture.mode {
            Task { await LiveCapture.run(mode: live, controller: controller) }
            return
        }

        if DragProbe.isRequested {
            Task { await DragProbe.run() }
            return
        }

        if UIProbe.isRequested {
            Task { await UIProbe.run(controller: controller) }
            return
        }

        if SelfTest.isRequested {
            Task { await SelfTest.run(controller: controller) }
            return
        }

        if let directory = SnapshotRunner.requestedDirectory {
            Task { await SnapshotRunner.run(into: directory) }
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

        let summonOK = center.register(.summon, combo: model.settings.summonHotKey) { [weak self] in
            self?.panelController?.toggle()
        }
        if !summonOK {
            model.show(Toast(
                text: "\(model.settings.summonHotKey.displayString) is taken by another app",
                symbol: "keyboard.badge.exclamationmark",
                tone: .warning,
                detail: "Choose a different shortcut in Settings"
            ))
        }

        if model.settings.quickSaveEnabled {
            center.register(.quickSave, combo: model.settings.quickSaveHotKey) {
                Services.model.quickSaveSelection()
            }
        } else {
            center.unregister(.quickSave)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Summon lives in the menu bar; closing the library window is not quitting.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Services.model.showMainWindowHandler?() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
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
