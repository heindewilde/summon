import AppKit
import SwiftUI
import SummonKit
import SummonUI

/// Development helper for reviewing the surfaces `ImageRenderer` cannot draw —
/// `NavigationSplitView` and `List`. It puts the real view in a real window and
/// writes that window's number to `SUMMON_LIVE_INFO`, so the harness can capture
/// exactly that window rather than the whole screen.
///
/// `SUMMON_APPEARANCE=dark` forces this app's appearance only, so reviewing dark
/// mode never touches the system setting. Never runs in normal use.
@MainActor
enum LiveCapture {
    static var mode: String? { ProcessInfo.processInfo.environment["SUMMON_LIVE"] }

    private static var heldWindow: NSWindow?

    static func run(mode: String, controller: PanelController) async {
        let model = Services.model

        if ProcessInfo.processInfo.environment["SUMMON_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        await model.seedStarterLibraryIfEmpty()
        try? await Task.sleep(for: .seconds(2))
        model.store.refresh()
        model.runSearch()

        let window: NSWindow?
        switch mode {
        case "panel":
            model.summon()
            try? await Task.sleep(for: .milliseconds(600))
            window = controller.debugPanel

        case "detail":
            model.sidebarSelection = .all
            model.mainSelection = model.itemsForSidebar()
                .first { $0.kind == .richText }?.id
                ?? model.itemsForSidebar().first?.id
            window = present(MainWindowView(model: model), size: CGSize(width: 1120, height: 700))

        case "grid":
            model.sidebarSelection = .all
            model.useGridLayout = true
            model.mainSelection = model.itemsForSidebar().first?.id
            window = present(MainWindowView(model: model), size: CGSize(width: 1120, height: 700))

        case "menubar":
            window = present(
                MenuBarView(model: model, openMainWindow: {}, openSettings: {}),
                size: CGSize(width: 330, height: 520)
            )

        case "settings":
            window = present(SettingsView(model: model), size: CGSize(width: 560, height: 420))

        default:
            model.sidebarSelection = .folder(
                model.store.allFolders().first { $0.name == "Client Replies" }?.id ?? UUID()
            )
            model.mainSelection = model.itemsForSidebar().first?.id
            window = present(MainWindowView(model: model), size: CGSize(width: 1120, height: 700))
        }

        try? await Task.sleep(for: .milliseconds(900))

        if let path = ProcessInfo.processInfo.environment["SUMMON_LIVE_INFO"],
           let number = window?.windowNumber {
            try? "\(number)".write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// A real AppKit window hosting the real SwiftUI view — the same arrangement the
    /// shipping app uses, so what gets captured is what ships.
    private static func present(_ view: some View, size: CGSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Summon"
        window.contentView = NSHostingView(rootView: AnyView(view))
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        heldWindow = window
        return window
    }
}
