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
        model.summon()
        try? await Task.sleep(for: .milliseconds(200))
        model.query = ""
        model.selectedIndex = 0

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
                return model.selectedIndex == 2
            }(), detail: model.results[2].item.title)
            _ = third
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

        model.dismissPanel()
        try? await Task.sleep(for: .milliseconds(200))
        check("Panel hides on dismiss", !controller.isVisible)

        print("=== \(checks - failures)/\(checks) checks passed ===\n")
        exit(failures == 0 ? 0 : 1)
    }
}
