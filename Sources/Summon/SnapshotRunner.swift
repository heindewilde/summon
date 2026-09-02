import AppKit
import SwiftUI
import SummonKit
import SummonUI

/// Development harness: renders each surface to PNG and exits.
///
/// Used to review the design without needing Screen Recording permission.
/// Activated with `SUMMON_SNAPSHOT=<directory>`; never runs in normal use.
@MainActor
enum SnapshotRunner {
    static var requestedDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["SUMMON_SNAPSHOT"] else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func run(into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = Services.model

        await model.seedStarterLibraryIfEmpty()
        model.runSearch()

        // Give a moment for background enrichment (OCR, thumbnails) to land.
        try? await Task.sleep(for: .seconds(3))
        model.store.refresh()
        model.runSearch()

        for scheme in [Appearance.light, Appearance.dark] {
            render(PanelBackground(), name: "diag-background", scheme: scheme,
                   size: CGSize(width: 300, height: 200))

            model.query = ""
            model.mode = .search
            model.selectedIndex = 0
            model.runSearch()
            render(PanelView(model: model), name: "panel-empty", scheme: scheme,
                   size: CGSize(width: PanelView.width, height: PanelView.height))

            model.query = "repl"
            model.runSearch()
            model.selectedIndex = 0
            render(PanelView(model: model), name: "panel-search", scheme: scheme,
                   size: CGSize(width: PanelView.width, height: PanelView.height))

            // A snippet with fill-in fields.
            if let template = model.store.snapshots.first(where: { $0.hasPlaceholders }) {
                model.query = ""
                model.runSearch()
                model.fieldValues = ["first_name": "Marieke", "project": "the rebrand"]
                model.mode = .fill(itemID: template.id)
                render(PanelView(model: model), name: "panel-fill", scheme: scheme,
                       size: CGSize(width: PanelView.width, height: PanelView.height))
            }

            model.mode = .unlock(pendingItemID: nil)
            render(PanelView(model: model), name: "panel-unlock", scheme: scheme,
                   size: CGSize(width: PanelView.width, height: PanelView.height))
            model.mode = .search

            // Documents folder, so the preview shows a real PDF.
            if let documents = model.store.allFolders().first(where: { $0.name == "Documents" }) {
                model.sidebarSelection = .folder(documents.id)
            }
            model.mainSelection = model.itemsForSidebar().first?.id
            render(MainWindowView(model: model), name: "main-window", scheme: scheme,
                   size: CGSize(width: 1080, height: 680))

            model.sidebarSelection = .all
            model.useGridLayout = true
            model.mainSelection = model.itemsForSidebar().first?.id
            render(MainWindowView(model: model), name: "main-grid", scheme: scheme,
                   size: CGSize(width: 1080, height: 680))
            model.useGridLayout = false

            render(MenuBarView(model: model, openMainWindow: {}, openSettings: {}),
                   name: "menubar", scheme: scheme, size: CGSize(width: 330, height: 520))

            render(OnboardingView(model: model), name: "onboarding", scheme: scheme,
                   size: CGSize(width: 620, height: 470))

            render(SettingsView(model: model), name: "settings", scheme: scheme,
                   size: CGSize(width: 560, height: 420))
        }

        print("Intelligence status: \(model.intelligence.status)")
        print("Items: \(model.store.snapshots.count)")
        for snap in model.store.snapshots.sorted(by: { $0.title < $1.title }) {
            print("  · \(snap.title) [\(snap.kind.rawValue)] tags=\(snap.tagNames) extracted=\(snap.searchableText.count)ch")
        }
        print("Snapshots written to \(directory.path)")
        NSApp.terminate(nil)
    }

    enum Appearance: String {
        case light, dark
        var nsAppearance: NSAppearance? {
            NSAppearance(named: self == .dark ? .darkAqua : .aqua)
        }
        var backing: Color {
            self == .dark
                ? Color(nsColor: NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1))
                : Color(nsColor: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1))
        }
    }

    /// Renders with `ImageRenderer`.
    ///
    /// This draws SwiftUI's own layout, which covers the panel, menu bar, onboarding
    /// and settings. It cannot draw AppKit-backed containers — `NavigationSplitView`
    /// and `List` — so the library window is reviewed live instead.
    private static func render(_ view: some View, name: String, scheme: Appearance, size: CGSize) {
        guard let appearance = scheme.nsAppearance, let directory = requestedDirectory else { return }
        appearance.performAsCurrentDrawingAppearance {
            let wrapped = ZStack {
                scheme.backing
                view
            }
            .environment(\.colorScheme, scheme == .dark ? .dark : .light)
            .environment(\.isSnapshotting, true)
            .frame(width: size.width, height: size.height)

            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: directory.appending(path: "\(name)-\(scheme.rawValue).png"))
        }
    }
}
