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

        // MARK: Encrypting while the vault is locked
        //
        // This used to fly the summon panel in over the library to announce that
        // everything was about to be unlocked, when all anyone had done was flick one
        // switch on one item. The window asks, and it asks about that item.
        if !model.vault.isConfigured,
           let subject = model.store.snapshots.first(where: { $0.kind.isTextual }) {
            await model.completeSecretSetup(secret: "1379") { _ in }
            model.setItemSensitive(subject.id, true)
            model.vault.lock()
            model.store.refresh()
            model.dismissPanel()

            // Now ask to decrypt it, with the vault shut.
            model.setItemSensitive(subject.id, false)
            check("A locked vault asks in the window, not the panel",
                  model.lockSheet != nil && !controller.isVisible,
                  detail: "sheet: \(model.lockSheet.map(\.id) ?? "none"), panel: \(controller.isVisible)")
            if case .unlock(let reason) = model.lockSheet {
                check("The prompt names what you asked for, not the whole vault",
                      reason.contains("decrypt") && !reason.lowercased().contains("everything"),
                      detail: reason)
            } else {
                check("The prompt names what you asked for, not the whole vault", false,
                      detail: "no unlock sheet")
            }

            // Entering the PIN finishes the interrupted action.
            check("Unlocking from the sheet completes the action",
                  await model.unlockInPlace(secret: "1379")
                      && model.store.item(id: subject.id)?.isSensitive == false)
            model.finishLockSheet()

            // And the way back out, from a locked vault, asks for the PIN first.
            model.vault.lock()
            check("Turning the PIN off while locked starts by asking for it",
                  !model.vault.isUnlocked)
            model.removeVaultProtection()
            check("It refuses to discard the key while it cannot decrypt",
                  model.vault.isConfigured)

            try? await model.vault.unlock(pin: "1379")
            model.removeVaultProtection()
            model.store.refresh()
        }

        // MARK: An encrypted image is readable again the moment it is unlocked
        //
        // The detail pane loaded its preview once, keyed on which item was selected.
        // Unlocking does not change the selection, so nothing re-ran: the image stayed
        // blank until you clicked away and back, which re-selected it. The data was
        // always there — this checks the half the view depends on.
        if let image = model.store.snapshots.first(where: { $0.kind == .image }) {
            if !model.vault.isConfigured { await model.completeSecretSetup(secret: "1379") { _ in } }
            model.setItemSensitive(image.id, true)
            check("An image can be encrypted", model.store.item(id: image.id)?.blobSealed == true)

            model.vault.lock()
            model.store.refresh()
            check("Locked, it offers no preview", model.previewData(for: image.id).fileURL == nil)

            try? await model.vault.unlock(pin: "1379")
            model.store.refresh()
            let unlocked = model.previewData(for: image.id)
            check("Unlocked, the file is materialised again",
                  unlocked.fileURL != nil
                      && FileManager.default.fileExists(atPath: unlocked.fileURL?.path ?? ""),
                  detail: unlocked.fileURL?.lastPathComponent ?? "nothing")
            check("And the snapshot stops reporting it as locked",
                  model.store.snapshots.first { $0.id == image.id }?.isLocked == false)

            model.setItemSensitive(image.id, false)
            model.removeVaultProtection()
            model.store.refresh()
        }

        // MARK: The detail pane fits the window it is given
        //
        // A grouped `Form` carries its own scroll view, and asking a scroll view for
        // its ideal height gets an effectively unbounded answer. Inside the detail
        // pane that propagated all the way up: the window grew past the screen and
        // dragged the sidebar off the left edge with it. The pane must never demand
        // more than the window it is placed in.
        do {
            let given = CGSize(width: 1120, height: 700)
            var worst: (kind: String, height: CGFloat) = ("none", 0)
            for kind in ItemKind.allCases {
                model.sidebarSelection = .all
                guard let subject = model.itemsForSidebar().first(where: { $0.kind == kind })
                else { continue }
                model.mainSelection = subject.id

                let host = NSHostingView(rootView: MainWindowView(model: model))
                host.frame = CGRect(origin: .zero, size: given)
                host.layoutSubtreeIfNeeded()
                let needed = host.fittingSize.height
                if needed > worst.height { worst = (kind.rawValue, needed) }
            }
            check("The library window fits the size it is given",
                  worst.height <= given.height,
                  detail: String(format: "worst is %@ at %.0f pt against %.0f",
                                 worst.kind as NSString, worst.height, given.height))
            model.mainSelection = nil
            model.sidebarSelection = .all
        }

        // MARK: Turning the PIN back off
        //
        // The way out. Removing the key file with content still sealed would leave it
        // unreadable forever, so the decrypt has to happen first — and be counted, so
        // the confirmation can say what it is about to do.
        if !model.vault.isConfigured,
           let victim = model.store.snapshots.first(where: { $0.kind.isTextual }) {
            await model.completeSecretSetup(secret: "2468") { _ in }
            model.setItemSensitive(victim.id, true)
            let sealed = model.store.item(id: victim.id)?.sealedBody != nil
            check("An item can be encrypted once a PIN exists", sealed)

            let decrypted = model.removeVaultProtection()
            check("Turning off the PIN reports what it decrypted", decrypted == 1,
                  detail: "\(decrypted.map(String.init) ?? "nil") items")
            check("Turning off the PIN leaves no vault", !model.vault.isConfigured)
            model.store.refresh()
            let after = model.store.snapshots.first { $0.id == victim.id }
            check("And the contents are readable again with no key at all",
                  after?.isLocked == false && after?.searchableText.isEmpty == false)
        }

        // MARK: Appearance
        //
        // Applied to the application, not to a view tree: the panel is its own window,
        // so a `.preferredColorScheme` on the library would leave it in the system's
        // appearance while the library changed.
        let originalAppearance = model.settings.appearance
        model.settings.appearance = .dark
        check("Choosing Dark switches the app's appearance",
              NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
              detail: NSApp.effectiveAppearance.name.rawValue)
        model.settings.appearance = .light
        check("Choosing Light switches it back",
              NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
              detail: NSApp.effectiveAppearance.name.rawValue)
        model.settings.appearance = .system
        check("Match System hands the choice back to macOS", NSApp.appearance == nil)
        model.settings.appearance = originalAppearance

        // MARK: Marking something sensitive with no PIN yet
        //
        // This did nothing at all: the action asked for an unlocked vault, there was
        // no PIN to unlock it with, and the request was recorded in a flag that
        // nothing read. The encryption worked; there was simply no way to get a key.
        if !model.vault.isConfigured,
           let subject = model.store.snapshots.first(where: { $0.kind.isTextual && !$0.isSensitive }) {
            model.setItemSensitive(subject.id, true)
            check("Marking an item sensitive with no PIN asks for one",
                  model.lockSheet == .create,
                  detail: "sheet: \(model.lockSheet.map(\.id) ?? "none")")
            check("It does not silently mark the item first",
                  model.store.item(id: subject.id)?.isSensitive == false)

            await model.completeSecretSetup(secret: "1379") { message in
                check("Setting the PIN succeeded", false, detail: message)
            }
            try? await Task.sleep(for: .milliseconds(120))
            check("Setting the PIN closes the sheet", model.lockSheet == nil)
            check("Setting the PIN finishes what you asked for",
                  model.store.item(id: subject.id)?.isSensitive == true,
                  detail: "sensitive: \(model.store.item(id: subject.id)?.isSensitive == true)")
            check("And the contents are actually encrypted",
                  model.store.item(id: subject.id)?.sealedBody != nil)

            // Put it back, so the vault section below starts from a known shape.
            model.setItemSensitive(subject.id, false)
            // Decrypted first, on the line above: removing the PIN with content still
            // sealed would leave it unreadable.
            try? model.vault.removePIN()
            model.store.refresh()
        } else {
            check("Marking an item sensitive with no PIN asks for one", false,
                  detail: "a vault was already configured")
        }

        // Cancelling has to leave nothing behind.
        if !model.vault.isConfigured,
           let subject = model.store.snapshots.first(where: { $0.kind.isTextual }) {
            model.setItemSensitive(subject.id, true)
            model.cancelLockSheet()
            check("Cancelling the PIN sheet leaves the item alone",
                  model.lockSheet == nil && model.store.item(id: subject.id)?.isSensitive == false)
        }

        // MARK: Vault, end to end
        let vaultPIN = "4829"
        if !model.vault.isConfigured {
            try? await model.vault.setUpPIN(vaultPIN)
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

            try? await model.vault.unlock(pin: vaultPIN)
            model.store.refresh()
            let unlocked = model.store.snapshots.first { $0.id == victim.id }
            check("Unlocking restores the contents", unlocked?.searchableText.isEmpty == false)
            check("Insert works again once unlocked", model.store.payload(for: victim.id) != nil)

            model.vault.lock()
            model.store.refresh()
            check("A locked item refuses to drag its contents",
                  model.dragProvider(for: victim.id) == nil)
            // It can still be dragged into a folder, though: filing something reveals
            // nothing about it, and being unable to tidy a locked item without first
            // unlocking it was a rule with no reason behind it.
            check("A locked item can still be dragged to file it",
                  model.identityOnlyDragProvider(for: victim.id)
                      .registeredTypeIdentifiers.contains(SummonDragType.item.identifier))
            try? await model.vault.unlock(pin: vaultPIN)
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

        // MARK: What a drag actually puts on the pasteboard
        //
        // Registering a type on an NSItemProvider and having the drop side *recognise*
        // it are two different things: the identifier has to be declared in the bundle
        // and known to the type system, or `hasItemsConforming(to:)` on the receiving
        // side quietly answers no and the drop is never offered to our delegate.
        info("item type declared", "\(SummonDragType.item.isDeclared), dynamic: \(SummonDragType.item.isDynamic)")
        info("folder type declared", "\(SummonDragType.folder.isDeclared), dynamic: \(SummonDragType.folder.isDynamic)")
        check("The item drag type is a real declared type",
              SummonDragType.item.isDeclared && !SummonDragType.item.isDynamic,
              detail: SummonDragType.item.identifier)

        if let any = model.store.snapshots.first(where: { !$0.isLocked }),
           let provider = model.dragProvider(for: any.id) {
            check("The provider reports the item type",
                  provider.hasItemConformingToTypeIdentifier(SummonDragType.item.identifier),
                  detail: provider.registeredTypeIdentifiers.joined(separator: ", "))

            let readBack = await SummonDrag.id(from: [provider], type: SummonDragType.item)
            check("The item id survives the round trip", readBack == any.id,
                  detail: readBack.map(String.init(describing:)) ?? "nothing came back")

        }

        // MARK: Filing an item by dragging it onto a folder
        //
        // The drag has to carry the row's identity, not only its contents — that was
        // the whole reason dropping an item on a folder did nothing.
        if let subject = model.store.snapshots.first(where: { $0.kind.isTextual && !$0.isLocked }) {
            let types = model.dragProvider(for: subject.id)?.registeredTypeIdentifiers ?? []
            check("An item's drag carries which item it is",
                  types.contains(SummonDragType.item.identifier),
                  detail: types.joined(separator: ", "))

            model.fileItem(subject.id, into: top)
            check("Dragging an item onto a folder files it there",
                  model.store.item(id: subject.id)?.folder?.id == top.id,
                  detail: model.store.item(id: subject.id)?.folder?.name ?? "nowhere")

            model.sidebarSelection = .folder(top.id)
            check("The folder now shows it", model.itemsForSidebar().contains { $0.id == subject.id })

            // A parent must not absorb what is filed beneath it.
            model.store.moveFolder(inner, under: top)
            let nested = model.store.createSnippet(title: "Nested probe", body: "…", folder: inner)
            model.store.refresh()
            model.sidebarSelection = .folder(top.id)
            check("A parent folder shows its own items only",
                  !model.itemsForSidebar().contains { $0.id == nested.id },
                  detail: "\(model.itemsForSidebar().count) items in \(model.sidebarTitle)")
            model.sidebarSelection = .folder(inner.id)
            check("The child folder is where the nested item lives",
                  model.itemsForSidebar().contains { $0.id == nested.id })

            // And the count beside the row has to agree with the list it opens.
            let row = model.sidebarFolderRows.first { $0.id == top.id }
            model.sidebarSelection = .folder(top.id)
            check("A folder's count matches the list it opens",
                  row?.itemCount == model.itemsForSidebar().count,
                  detail: "badge \(row?.itemCount ?? -1), list \(model.itemsForSidebar().count)")

            model.store.delete(nested)
            model.fileItem(subject.id, into: nil)
            model.sidebarSelection = .all
        }

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

            // What a drag costs per frame. `dropUpdated` fires continuously while you
            // hold a row, and every one of those re-evaluates the sidebar — so this
            // number, not the drop itself, is what "dragging feels laggy" measures.
            // It used to walk the folder table and recursively count items for every
            // row, on every frame; now the rows are a cached list of values.
            // What one tag edit costs. The tag field used to report a change on every
            // keystroke and write the list each time, so typing a five-letter tag paid
            // this five times over; it now writes once, when a tag is added or removed.
            if let tagged = model.store.item(id: snippet.id) {
                let names = tagged.tagNames
                info("setTags (was once per keystroke)", String(format: "%.2f ms", milliseconds(5) {
                    model.store.setTags(tagged, names: names)
                }))
            }

            let perFrame = milliseconds(200) { _ = model.sidebarFolderRows }
            info("sidebar rows (drag frame)", String(format: "%.4f ms", perFrame))
            check("A drag frame costs well under a frame's budget",
                  perFrame < 1.0,
                  detail: String(format: "%.4f ms per rebuild, 16.7 ms available", perFrame))

            // The same work the old sidebar did inline, for comparison: fetch the
            // folder table, sort it, and recursively count every item under each row.
            let uncached = milliseconds(200) {
                var total = 0
                func walk(_ folders: [SummonFolder]) {
                    for folder in folders {
                        total += folder.allItems().count
                        walk(folder.sortedChildren)
                    }
                }
                walk(model.store.rootFolders())
            }
            info("sidebar rows (uncached, as it was)", String(format: "%.4f ms", uncached))

            let cold = milliseconds(20) {
                model.store.refresh()
                _ = model.sidebarFolderRows
            }
            info("sidebar rows (after a change)", String(format: "%.2f ms", cold))
        }

        // MARK: The unlock pane takes focus, in both shapes
        //
        // A screenshot cannot answer this. An AppKit focus ring only draws while the
        // window is key, so a passphrase field that never took focus and one that did
        // look identical in a still frame — and a field nobody can type into is a
        // vault nobody can open.
        for kind in VaultSecretKind.allCases {
            model.removeVaultProtection()
            let secret = kind == .pin ? "1379" : "correct horse battery"
            try? await model.vault.setUpSecret(secret, kind: kind)
            model.vault.lock()

            NSApp.activate()
            model.summon()
            model.mode = .unlock(pendingItemID: nil)
            // The field focuses itself a beat after appearing, on purpose: a panel is
            // not in the responder chain on its first pass.
            try? await Task.sleep(for: .milliseconds(600))

            let responder = controller.debugPanel?.firstResponder
            let editing = responder is NSTextView
            check("The \(kind.noun) field takes focus in the panel", editing,
                  detail: "first responder: \(responder.map { "\(type(of: $0))" } ?? "none")")

            model.mode = .search
            model.dismissPanel()
            try? await Task.sleep(for: .milliseconds(200))
        }
        model.removeVaultProtection()

        check("Panel hides on dismiss", !controller.isVisible)

        print("=== \(checks - failures)/\(checks) checks passed ===\n")
        exit(failures == 0 ? 0 : 1)
    }
}
