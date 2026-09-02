import AppKit
import SwiftUI
import SummonKit
import SummonUI

@main
struct SummonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = Services.model

    var body: some Scene {
        // Suppressed on launch. A `Window` scene otherwise opens itself, so the
        // library existed from the moment the app started — and because summoning
        // activates the app, it came forward with the panel every single time. The
        // library is a place you go deliberately, not something that arrives with a
        // hotkey meant to paste one line of text.
        Window("Summon Library", id: WindowID.main) {
            MainWindowView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .commands { SummonCommands(model: model) }

        Window("Welcome to Summon", id: WindowID.onboarding) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)

        // A plain menu, not a second copy of the library. Its list of pinned and
        // recent items duplicated exactly what the panel shows on an empty query,
        // which is one keystroke away. What a menu bar item is genuinely good at is
        // being a visible way in when you have forgotten the shortcut.
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: "sparkles")
                .accessibilityLabel("Summon")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }

}

enum WindowID {
    static let main = "summon.main"
    static let onboarding = "summon.onboarding"
}

/// Wraps the menu bar content so it can reach `openWindow`, which is only available
/// from inside a scene.
struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuBarMenu(
            model: model,
            openMainWindow: openLibrary,
            openSettings: {
                NSApp.activate()
                openSettings()
            }
        )
        .onAppear {
            // Wired from here, not from the library window: the handler that opens
            // the library cannot live on the thing it opens.
            model.showMainWindowHandler = openLibrary
            model.showOnboardingHandler = {
                NSApp.activate()
                openWindow(id: WindowID.onboarding)
            }
        }
    }

    private func openLibrary() {
        NSApp.activate()
        openWindow(id: WindowID.main)
    }
}

struct SummonCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Snippet") { model.beginNewSnippet() }
                .keyboardShortcut("n")
            Button("New Folder") { model.beginNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .newItem) {
            Button("Import Files…") { model.presentImportPanel() }
                .keyboardShortcut("o")
            Divider()
            // ⌘K is a solution to not having room, so it stays in the panel. A
            // window has room, and shows its actions instead of hiding them a level
            // down. ⌘L opens the library; ⌥Space stays the only way to the panel.
            Button(model.mainSelectionIsPinned ? "Unpin" : "Pin") {
                if let id = model.mainSelection { model.togglePin(id) }
            }
            .keyboardShortcut("p")
            .disabled(model.mainSelection == nil)
            Button("Delete") { model.requestDeleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.mainSelection == nil)
            Button(model.vault.isUnlocked ? "Lock Sensitive Items" : "Unlock Sensitive Items") {
                model.toggleLock()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!model.vault.isConfigured)
        }
    }
}
