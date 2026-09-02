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
        let environment2 = ProcessInfo.processInfo.environment
        // Never steal focus for a screenshot. Someone is usually working while these
        // run, and an activating window both interrupts them and puts their next
        // keystroke somewhere neither of us intended.
        NSApp.setActivationPolicy(.accessory)

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
            // SUMMON_LIVE_QUERY reviews the typed state — match highlighting and the
            // adaptive preview — not just the empty panel. SUMMON_LIVE_SELECT picks a
            // row, so an image or PDF selection can be reviewed with its preview open.
            //
            // The query is set *before* the panel is shown, deliberately. Assigning it
            // afterwards writes into an NSTextField that already owns an active field
            // editor, and the two fight: "stdtrm" arrived in the field as "stdty".
            // That is an artefact of injecting text this way, not something a person
            // typing can hit — `updateNSView` guards on `field.stringValue != text` —
            // but it produced a screenshot convincing enough to send me looking for a
            // bug in the panel that was never there.
            let environment = ProcessInfo.processInfo.environment
            model.focus.capture()
            model.mode = .search
            model.query = environment["SUMMON_LIVE_QUERY"] ?? ""
            model.runSearch()
            if let row = environment["SUMMON_LIVE_SELECT"], let index = Int(row) {
                model.selectedIndex = min(index, max(0, model.results.count - 1))
            }
            model.isPanelVisible = true
            // After isPanelVisible: openActionMenu() resolves its target through
            // actionTarget, which returns nil while the panel is not up.
            if environment["SUMMON_LIVE_OVERLAY"] == "actions" { model.openActionMenu() }
            controller.showForCapture()
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

        case "iconpicker":
            let folder = model.store.rootFolders().first
                ?? model.store.createFolder(name: "Example")
            window = present(
                FolderIconPicker(model: model, folder: folder,
                                 isPresented: .constant(true),
                                 initialQuery: environment2["SUMMON_LIVE_QUERY"] ?? "")
                    .background(Theme.chrome),
                size: CGSize(width: 288, height: 372)
            )

        case "menubar":
            window = present(
                MenuBarView(model: model, openMainWindow: {}, openSettings: {}),
                size: CGSize(width: 330, height: 520)
            )

        case "settings":
            window = present(SettingsView(model: model), size: CGSize(width: 560, height: 420))

        case "drop":
            // Freezes a drop indicator so its weight can actually be reviewed; a real
            // drag cannot be held still for a screenshot.
            model.sidebarSelection = .all
            if let target = model.store.rootFolders().dropFirst().first {
                let zone: FolderDropZone = switch environment2["SUMMON_LIVE_DROP"] ?? "before" {
                    case "into": .into
                    case "after": .after
                    default: .before
                }
                model.folderDropTarget = FolderDropTarget(folderID: target.id, zone: zone)
            }
            window = present(MainWindowView(model: model), size: CGSize(width: 1120, height: 700))

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
