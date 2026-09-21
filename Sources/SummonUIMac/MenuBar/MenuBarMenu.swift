import SummonKit
import SwiftUI
import SummonUI

/// The menu bar item, as a plain menu.
///
/// It used to be a 330pt popover listing pinned items, recent items and clipboard
/// history — which is exactly what the panel shows on an empty query, one keystroke
/// away. Three surfaces showed your items and it was never obvious which one you
/// were meant to be in.
///
/// What a menu bar item is actually good at is being visible: a way in when you have
/// forgotten the shortcut, and somewhere Settings and Quit reliably live.
public struct MenuBarMenu: View {
    @Bindable var model: AppModel
    let openMainWindow: () -> Void
    let openSettings: () -> Void

    public init(model: AppModel, openMainWindow: @escaping () -> Void,
                openSettings: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
        self.openSettings = openSettings
    }

    public var body: some View {
        Button("Summon…") { model.summon() }
            .keyboardShortcut(.space, modifiers: .option)

        Button("Library…", action: openMainWindow)
            .keyboardShortcut("l")

        Divider()

        Button("Save What's on the Clipboard") { model.saveCurrentClipboard() }
        Button("Save the Current Selection") { model.quickSaveSelection() }

        if model.vault.isConfigured {
            Divider()
            Button(model.vault.isUnlocked ? "Lock Sensitive Items" : "Unlock Sensitive Items") {
                model.toggleLock()
            }
        }

        Divider()

        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")

        Button("Quit Summon") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
