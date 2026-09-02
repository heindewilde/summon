import AppKit
import SwiftUI
import SummonKit
import SummonUI

@main
struct SummonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = Services.model

    var body: some Scene {
        Window("Summon", id: WindowID.main) {
            MainWindowView(model: model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { wireWindowHandlers() }
        }
        .defaultSize(width: 1180, height: 720)
        .commands { SummonCommands(model: model) }

        Window("Welcome to Summon", id: WindowID.onboarding) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: "sparkles")
                .accessibilityLabel("Summon")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private func wireWindowHandlers() {
        // Assigned here rather than in the delegate because opening a SwiftUI window
        // requires the environment action, which only exists inside a scene.
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
        MenuBarView(
            model: model,
            openMainWindow: {
                NSApp.activate()
                openWindow(id: WindowID.main)
            },
            openSettings: {
                NSApp.activate()
                openSettings()
            }
        )
        .onAppear {
            model.showMainWindowHandler = {
                NSApp.activate()
                openWindow(id: WindowID.main)
            }
            model.showOnboardingHandler = {
                NSApp.activate()
                openWindow(id: WindowID.onboarding)
            }
        }
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
            Button("Summon") { model.summon() }
                .keyboardShortcut("k")
            Button(model.vault.isUnlocked ? "Lock Sensitive Items" : "Unlock Sensitive Items") {
                model.toggleLock()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!model.vault.isConfigured)
        }
    }
}
