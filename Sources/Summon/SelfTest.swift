import AppKit
import SwiftUI
import SummonKit
import SummonUI

/// End-to-end runtime checks for the parts unit tests cannot reach: real hot key
/// registration, the panel window, and the full choose-then-insert path.
/// Activated with `SUMMON_SELFTEST=1`; never runs in normal use.
@MainActor
enum SelfTest {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["SUMMON_SELFTEST"] == "1"
    }

    private static var failures = 0
    private static var checks = 0

    static func check(_ label: String, _ condition: Bool, detail: String = "") {
        checks += 1
        if condition {
            print("  PASS  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        } else {
            failures += 1
            print("  FAIL  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func info(_ label: String, _ value: String) {
        print("  ····  \(label): \(value)")
    }

    static func run(controller: PanelController) async {
        let model = Services.model
        // Nothing this test does may reach outside the app: no clipboard writes, no
        // synthesised keystrokes into whatever is frontmost.
        model.isHarness = true
        print("\n=== Summon self-test ===")

        // MARK: Environment
        info("Library", model.paths.root.path)
        info("Accessibility granted", Inserter.hasAccessibility ? "yes" : "no (auto-paste falls back to copy)")
        info("Touch ID available", Vault.biometricsAvailable ? "yes" : "no")
        info("On-device model", "\(model.intelligence.status)")

        // MARK: Hot keys — the thing the app is named for
        let summonOK = HotKeyCenter.shared.register(.summon, combo: model.settings.summonHotKey) {}
        check("Global summon hot key registers (\(model.settings.summonHotKey.displayString))", summonOK)
        let saveOK = HotKeyCenter.shared.register(.quickSave, combo: model.settings.quickSaveHotKey) {}
        check("Global save hot key registers (\(model.settings.quickSaveHotKey.displayString))", saveOK)

        // MARK: Library
        await model.seedStarterLibraryIfEmpty()
        try? await Task.sleep(for: .seconds(2))
        model.store.refresh()
        model.runSearch()
        check("Starter library seeded", model.store.snapshots.count >= 8,
              detail: "\(model.store.snapshots.count) items")

        let withText = model.store.snapshots.filter { !$0.searchableText.isEmpty }
        check("Content is extracted for search", withText.count >= 8,
              detail: "\(withText.count) items carry searchable text")

        let pdf = model.store.snapshots.first { $0.kind == .document }
        check("PDF text was extracted", (pdf?.searchableText.count ?? 0) > 200,
              detail: "\(pdf?.searchableText.count ?? 0) characters")

        // MARK: The panel window
        //
        // The harness activates; the app deliberately does not. This binary is run
        // directly rather than through `open`, so it is never properly launched and
        // will not put a window on screen unless asked. In real use the panel appears
        // without activating — which is the point, since activating raises every
        // window the app owns. UIProbe checks that path against a real launch.
        NSApp.activate()
        model.summon()
        try? await Task.sleep(for: .milliseconds(400))
        check("Panel becomes visible on summon", controller.isVisible)

        if let panel = controller.debugPanel {
            check("Panel is a non-activating floating panel",
                  panel.styleMask.contains(.nonactivatingPanel) && panel.isFloatingPanel)
            check("Panel can take key focus so typing works", panel.canBecomeKey)
            check("Panel follows you across Spaces",
                  panel.collectionBehavior.contains(.canJoinAllSpaces))
            check("Panel is transparent so its rounded corners read correctly",
                  !panel.isOpaque && panel.backgroundColor == .clear)
        } else {
            check("Panel exists", false)
        }

        // MARK: Search behaviour
        model.query = "invoice"
        model.runSearch()
        check("Search finds a match for “invoice”", !model.results.isEmpty,
              detail: model.results.first.map { "top: \($0.item.title)" } ?? "none")

        model.query = "discovery call"   // text that exists only inside the PDF
        model.runSearch()
        check("Search reaches inside a PDF’s contents", !model.results.isEmpty,
              detail: model.results.first.map { "top: \($0.item.title)" } ?? "none")

        model.query = "pdf:"
        model.runSearch()
        check("The pdf: filter narrows to documents",
              !model.results.isEmpty && model.results.allSatisfy { $0.item.kind == .document })

        // MARK: Insert path
        model.query = ""
        model.runSearch()
        let scratch = NSPasteboard(name: NSPasteboard.Name("com.heindewilde.summon.selftest"))
        if let template = model.store.snapshots.first(where: { $0.hasPlaceholders }),
           let payload = model.store.payload(for: template.id,
                                             fieldValues: ["first_name": "Marieke",
                                                           "invoice_number": "2026-084"]) {
            model.inserter.writeToPasteboard(payload, to: scratch)
            let written = scratch.string(forType: .string) ?? ""
            check("A filled snippet reaches the pasteboard", !written.isEmpty)
            check("Placeholders are resolved, not pasted raw", !written.contains("{{"),
                  detail: String(written.prefix(48)).replacingOccurrences(of: "\n", with: " ") + "…")
        } else {
            check("A snippet with placeholders is available", false)
        }
        scratch.releaseGlobally()

        // MARK: Dragging carries content, not just a title
        if let pdf = model.store.snapshots.first(where: { $0.kind == .document }) {
            let provider = model.dragProvider(for: pdf.id)
            let types = provider?.registeredTypeIdentifiers ?? []
            check("A document row drags as a real file",
                  types.contains { $0.contains("pdf") || $0.contains("data") },
                  detail: types.first ?? "nothing registered")
        }
        if let snippet = model.store.snapshots.first(where: { $0.kind == .text }) {
            let types = model.dragProvider(for: snippet.id)?.registeredTypeIdentifiers ?? []
            check("A snippet row drags its text",
                  types.contains { $0.contains("text") }, detail: types.first ?? "nothing registered")
        }

        // MARK: Rich snippets keep their formatting through an edit
        if let rich = model.store.snapshots.first(where: { $0.kind == .richText }),
           let item = model.store.item(id: rich.id) {
            let before = model.store.resolveAttributed(item, key: model.vault.currentKey)
            check("A rich snippet exists and carries formatting", before != nil)

            if let before {
                let edited = NSMutableAttributedString(attributedString: before)
                edited.append(NSAttributedString(string: " ·"))
                model.store.updateSnippet(item, attributed: edited)

                let after = model.store.resolveAttributed(item, key: model.vault.currentKey)
                let keptFont = after.flatMap {
                    $0.length > 0 ? $0.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
                }
                check("Editing it does not discard the formatting",
                      item.kind == .richText && item.bodyRTF != nil
                          && keptFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
            }
        } else {
            check("A rich snippet exists and carries formatting", false)
        }

        // MARK: Vault, end to end
        let vaultPIN = "482913"
        if !model.vault.isConfigured {
            try? model.vault.setUpPIN(vaultPIN)
        }
        check("Vault configures and unlocks", model.vault.isUnlocked)

        if let victim = model.store.snapshots.first(where: { $0.kind.isTextual }),
           let item = model.store.item(id: victim.id) {
            try? model.store.setSensitive(item, true)
            check("Item body is encrypted at rest", item.sealedBody != nil && item.bodyText == nil)

            model.vault.lock()
            model.store.refresh()
            let locked = model.store.snapshots.first { $0.id == victim.id }
            check("Locked item keeps its title", locked?.title == victim.title)
            check("Locked item hides its contents", locked?.searchableText.isEmpty == true)
            check("Locked item cannot be inserted", model.store.payload(for: victim.id) == nil)

            try? model.vault.unlock(pin: vaultPIN)
            model.store.refresh()
            let unlocked = model.store.snapshots.first { $0.id == victim.id }
            check("Unlocking restores the contents", unlocked?.searchableText.isEmpty == false)
            check("Insert works again once unlocked", model.store.payload(for: victim.id) != nil)

            model.vault.lock()
            model.store.refresh()
            check("A locked item refuses to drag", model.dragProvider(for: victim.id) == nil)
            try? model.vault.unlock(pin: vaultPIN)
            model.store.refresh()
        }

        // MARK: The keyboard model, wired
        //
        // The panel drew ⌘1–⌘9 on every row for an entire release with no handler
        // behind them. These assert the bindings actually reach behaviour, not just
        // that PanelKeyMap resolves them — that is already unit-tested.
        // Re-establish the preconditions rather than inherit them: the vault and
        // folder sections above mutate the library, and these checks were passing or
        // failing depending on what those left behind.
        NSApp.activate()
        model.summon()
        model.store.refresh()
        model.query = ""
        model.runSearch()
        model.selectedIndex = 0
        // Wait for the state rather than guess at a delay: a fixed sleep passed on a
        // warm run and failed on the first one after a rebuild.
        for _ in 0..<40 where model.results.isEmpty || !model.isPanelVisible {
            try? await Task.sleep(for: .milliseconds(50))
            model.runSearch()
        }
        check("There is something to act on",
              !model.results.isEmpty && model.isPanelVisible,
              detail: "\(model.results.count) results, panel visible \(model.isPanelVisible)")

        check("⌘K opens the action menu", {
            model.route(KeyChord(.character("k"), .command))
            return model.overlay == .actions
        }())
        check("The action list is populated", !model.actionResults.isEmpty,
              detail: "\(model.actionResults.count) actions")
        check("⌘K again closes it", {
            model.route(KeyChord(.character("k"), .command))
            return model.overlay == .none
        }())

        check("⎋ closes the menu before it closes the panel", {
            model.openActionMenu()
            model.escape()
            return model.overlay == .none && model.isPanelVisible
        }())

        if model.results.count > 2 {
            let third = model.results[2].id
            check("⌘3 activates the third result", {
                model.route(KeyChord(.character("3"), .command))
                return model.selectedIndex == 2 && model.lastDelivery?.id == third
            }(), detail: model.results[2].item.title)
        }

        check("⌘↑ and ⌘↓ jump to the ends", {
            model.route(KeyChord(.down, .command))
            let atEnd = model.selectedIndex == model.results.count - 1
            model.route(KeyChord(.up, .command))
            return atEnd && model.selectedIndex == 0
        }())

        check("The panel declines ⌘C so the field keeps it",
              !model.route(KeyChord(.character("c"), .command)))

        if let foldered = model.results.first(where: { !$0.item.folderPath.isEmpty }) {
            model.selectedIndex = model.results.firstIndex { $0.id == foldered.id } ?? 0
            check("⇥ scopes the search to the item's folder", {
                model.route(KeyChord(.tab))
                return model.folderScope == foldered.item.folderPath.last
            }(), detail: model.folderScope ?? "none")
            check("Everything shown is from that folder",
                  !model.results.isEmpty && model.results.allSatisfy {
                      $0.item.folderPath.last == model.folderScope
                  })
            check("⌫ on an empty query leaves the folder", {
                model.route(KeyChord(.delete))
                return model.folderScope == nil
            }())
        }

        // MARK: State that must not survive a dismissal
        check("Refining a query goes back to the best match", {
            model.query = ""
            model.selectedIndex = 3
            model.query = "e"
            return model.selectedIndex == 0
        }())

        model.query = ""
        if let foldered = model.results.first(where: { !$0.item.folderPath.isEmpty }) {
            model.selectedIndex = model.results.firstIndex { $0.id == foldered.id } ?? 0
            model.route(KeyChord(.tab))
            let scoped = model.folderScope != nil
            model.openActionMenu()
            model.dismissPanel()
            model.summon()
            try? await Task.sleep(for: .milliseconds(150))
            check("A folder scope does not leak into the next summon",
                  scoped && model.folderScope == nil)
            check("An open action menu does not leak into the next summon",
                  model.overlay == .none)
        }

        // MARK: The library window is reachable from the keyboard
        model.dismissPanel()
        try? await Task.sleep(for: .milliseconds(100))
        model.sidebarSelection = .all
        model.useGridLayout = true
        let visible = model.visibleItems
        if visible.count > 3 {
            model.mainSelection = visible[0].id
            check("Arrow keys move the grid selection", {
                model.moveMainSelection(by: 1)
                return model.mainSelection == visible[1].id
            }(), detail: "the grid used to be mouse-only")
            check("Grid selection stops at the ends rather than wrapping", {
                model.moveMainSelection(by: -50)
                return model.mainSelection == visible[0].id
            }())
            check("Deleting from the library asks first, in a real alert", {
                model.requestDeleteSelected()
                let asked = model.pendingDeleteID == visible[0].id
                model.pendingDeleteID = nil
                return asked
            }())
        }
        model.useGridLayout = false

        // MARK: Folders can be restructured
        let top = model.store.createFolder(name: "Probe Top")
        let inner = model.store.createFolder(name: "Probe Inner", parent: top)
        check("A folder nests under another", inner.parent?.id == top.id)
        check("A folder refuses to nest inside its own descendant",
              !model.store.canMoveFolder(top, under: inner))
        model.store.moveFolder(inner, under: nil)
        check("A nested folder can be dragged back to the top level", inner.parent == nil)
        model.store.reorderFolder(inner, relativeTo: top, placeAfter: false)
        let order = model.store.children(of: nil).map(\.id)
        check("Reordering persists an explicit order",
              (order.firstIndex(of: inner.id) ?? 99) < (order.firstIndex(of: top.id) ?? 0))
        check("A folder's icon and colour can be changed", {
            model.store.setFolderIcon(top, symbolName: "building.columns", colorName: "teal")
            return top.symbolName == "building.columns" && top.colorName == "teal"
        }())
        check("Every icon the picker offers is a real symbol",
              FolderIcon.all.allSatisfy {
                  NSImage(systemSymbolName: $0.name, accessibilityDescription: nil) != nil
              }, detail: "\(FolderIcon.all.count) icons")
        check("Icon search matches meaning, not just the symbol's name",
              FolderIcon.search("money").contains { $0.name == "dollarsign.circle" })

        model.store.deleteFolder(inner)
        model.store.deleteFolder(top)

        // MARK: A new item lands somewhere you can see it
        model.sidebarSelection = .pinned
        model.beginNewSnippet()
        try? await Task.sleep(for: .milliseconds(150))
        check("Creating from a filtered section moves you to where the item went",
              model.visibleItems.contains { $0.id == model.mainSelection },
              detail: "section is now \(model.sidebarTitle)")
        if let created = model.mainSelection {
            model.discardIfEmpty(created)
            check("An untouched new snippet removes itself again",
                  model.store.item(id: created) == nil)
        }
        model.sidebarSelection = .all

        // MARK: What clicking around the library actually costs
        func milliseconds(_ iterations: Int, _ body: () -> Void) -> Double {
            let start = ContinuousClock.now
            for _ in 0..<iterations { body() }
            let each = (ContinuousClock.now - start) / iterations
            return Double(each.components.attoseconds) / 1e15
        }

        if let document = model.store.snapshots.first(where: { $0.kind == .document }),
           let snippet = model.store.snapshots.first(where: { $0.kind == .text }) {
            info("previewData", String(format: "%.2f ms", milliseconds(5) {
                _ = model.previewData(for: document.id)
            }))
            info("store.refresh", String(format: "%.2f ms", milliseconds(5) {
                model.store.refresh()
            }))
            info("copy an item", String(format: "%.2f ms", milliseconds(5) {
                model.use(snippet.id, style: .copy)
            }))
            info("select an item", String(format: "%.2f ms", milliseconds(5) {
                model.mainSelection = snippet.id
                _ = model.visibleItems
            }))
        }

        check("Panel hides on dismiss", !controller.isVisible)

        print("=== \(checks - failures)/\(checks) checks passed ===\n")
        exit(failures == 0 ? 0 : 1)
    }
}
