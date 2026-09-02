import AppKit
import SummonKit
import SummonUI

/// Walks the library window's accessibility tree and reports what a person can
/// actually reach — by pointer and by keyboard.
///
/// Written because "I cannot reach the saved items, by mouse or keyboard" is not a
/// thing you can answer by reading SwiftUI code: the question is what AppKit ends up
/// exposing. `SUMMON_UIPROBE=1`; never runs in normal use.
@MainActor
enum UIProbe {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["SUMMON_UIPROBE"] == "1" }

    /// Posting real mouse and keyboard events is opt-in, because they go to whatever
    /// is under the pointer or frontmost — not necessarily to this app.
    static var mayPostInput: Bool {
        ProcessInfo.processInfo.environment["SUMMON_UIPROBE_INPUT"] == "1"
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private static func role(_ element: AXUIElement) -> String {
        (attribute(element, kAXRoleAttribute as String) as? String) ?? "?"
    }

    private static func title(_ element: AXUIElement) -> String {
        (attribute(element, kAXTitleAttribute as String) as? String)
            ?? (attribute(element, kAXDescriptionAttribute as String) as? String)
            ?? (attribute(element, kAXValueAttribute as String) as? String)
            ?? ""
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Every descendant, with its depth.
    private static func walk(_ element: AXUIElement, depth: Int = 0, into found: inout [(Int, AXUIElement)]) {
        guard depth < 24 else { return }
        for child in children(element) {
            found.append((depth, child))
            walk(child, depth: depth + 1, into: &found)
        }
    }

    static func run(controller: PanelController) async -> Never {
        let model = Services.model
        model.isHarness = true
        await model.seedStarterLibraryIfEmpty()
        try? await Task.sleep(for: .seconds(2))
        model.store.refresh()
        model.sidebarSelection = .all
        model.mainSelection = nil
        let handlerSet = model.showMainWindowHandler != nil
        model.showMainWindowHandler?()
        // A first click on a background window only activates it — AppKit does not
        // deliver it to the view unless acceptsFirstMouse is true. Without this the
        // probe reports "clicking changed nothing" for a perfectly working list.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSApp.windows.first { $0.title.contains("Summon") }?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(2))

        var report = ""
        func line(_ text: String) { report += text + "\n"; print(text) }

        guard AXIsProcessTrusted() else {
            line("SKIP  Accessibility is not granted, so the tree cannot be read")
            try? report.write(toFile: "/tmp/summon-uiprobe.txt", atomically: true, encoding: .utf8)
            exit(2)
        }

        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let windows = (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
        line("open-library handler wired: \(handlerSet)")
        line("windows: \(windows.count)")
        for window in windows { line("  · \(role(window))  “\(title(window))”") }

        guard let library = windows.first(where: { title($0).contains("Summon") && role($0) == "AXWindow" })
                ?? windows.first else {
            line("FAIL  no window to inspect")
            try? report.write(toFile: "/tmp/summon-uiprobe.txt", atomically: true, encoding: .utf8)
            exit(1)
        }

        var found: [(Int, AXUIElement)] = []
        walk(library, into: &found)
        line("elements in the library window: \(found.count)")

        let interesting = ["AXRow", "AXCell", "AXTable", "AXOutline", "AXList", "AXScrollArea", "AXGroup"]
        var counts: [String: Int] = [:]
        for (_, element) in found { counts[role(element), default: 0] += 1 }
        for role in interesting where counts[role] != nil {
            line("  \(role): \(counts[role]!)")
        }

        let titles = model.visibleItems.map(\.title)
        line("items the model says are visible: \(titles.count)")

        // Is any element in the tree actually labelled with an item title?
        var reachable: [String] = []
        for (_, element) in found {
            let text = title(element)
            if let match = titles.first(where: { !$0.isEmpty && text.contains($0) }) {
                if !reachable.contains(match) { reachable.append(match) }
            }
        }
        line(reachable.isEmpty
             ? "FAIL  none of the item titles appear anywhere in the window's accessibility tree"
             : "PASS  \(reachable.count) of \(titles.count) item titles are exposed — e.g. “\(reachable[0])”")

        // Does anything expose a press action, i.e. can a pointer or VoiceOver act on it?
        var actionable = 0
        for (_, element) in found where !title(element).isEmpty {
            var names: CFArray?
            if AXUIElementCopyActionNames(element, &names) == .success,
               let list = names as? [String], list.contains(kAXPressAction as String) {
                actionable += 1
            }
        }
        line("elements exposing a press action: \(actionable)")

        // Sidebar first: folder rows gained .onDrag, which is exactly what swallowed
        // the selection click on item rows.
        let sidebarBefore = model.sidebarSelection
        for (_, element) in found where mayPostInput {
            guard title(element).contains("Client Replies"),
                  let box = frame(of: element), box.width > 100, box.width < 320 else { continue }
            let point = CGPoint(x: box.midX, y: box.midY)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type,
                        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(700))
            line(model.sidebarSelection != sidebarBefore
                 ? "PASS  clicking a folder in the sidebar selects it"
                 : "FAIL  clicking a folder in the sidebar changed nothing")
            break
        }

        // The decisive test: put the pointer on a row and click it. Everything above
        // only says the row exists.
        let before = model.mainSelection
        var clicked = false
        // Matched by label rather than by role: the middle column is a LazyVStack now,
        // not a List, so there are no AXRows in it to look for.
        for (_, element) in found where mayPostInput {
            let label = title(element)
            guard titles.contains(where: { !$0.isEmpty && label.contains($0) }) else { continue }
            guard let frame = frame(of: element), frame.width > 250, frame.height > 20 else { continue }
            let origin = frame.origin
            let size = frame.size

            let point = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            let onScreen = NSScreen.screens.contains { screen in
                // AX is top-left origin; NSScreen is bottom-left. Convert to compare.
                let flipped = NSRect(x: screen.frame.minX,
                                     y: (NSScreen.screens[0].frame.maxY - screen.frame.maxY),
                                     width: screen.frame.width, height: screen.frame.height)
                return flipped.contains(point)
            }
            line("clicking a row at \(Int(point.x)), \(Int(point.y)) — \(Int(size.width))×\(Int(size.height)), on a screen: \(onScreen)")
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type,
                        mouseCursorPosition: point, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
            clicked = true
            break
        }

        if clicked {
            try? await Task.sleep(for: .milliseconds(700))
            let after = model.mainSelection
            line(after != nil && after != before
                 ? "PASS  clicking a row selects it"
                 : "FAIL  clicking a row changed nothing (selection is still \(String(describing: before)))")
        } else {
            line("FAIL  found no item row with a clickable frame")
        }

        // Does summoning drag the library window forward with it?
        line("app windows: " + NSApp.windows.map { "\($0.title.isEmpty ? "(untitled)" : $0.title)[\($0.isVisible)]" }.joined(separator: ", "))
        let libraryWindow = NSApp.windows.first { $0.isVisible && !($0 is SummonPanel) && $0.contentView != nil }
        libraryWindow?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(400))

        // Step out of the way first, the way another app would be frontmost in real
        // use. If summoning re-activates us, every window this app owns comes forward
        // with the panel — which is what put the library on top of your work.
        model.dismissPanel()
        let libraryOpenBefore = NSApp.windows.contains { $0.isVisible && !($0 is SummonPanel) && !$0.title.isEmpty }
        line("library window open before summon: \(libraryOpenBefore)")
        // The probe forced .regular earlier so it could click; a menu-bar app is
        // .accessory, and the distinction decides whether ordering a window front
        // activates the whole app.
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
        try? await Task.sleep(for: .milliseconds(800))
        let wasActive = NSApp.isActive

        model.summon()
        try? await Task.sleep(for: .seconds(1))
        // What the person actually sees: where Summon's windows sit in the on-screen
        // stack across every application. NSApp.isActive does not answer that.
        func onScreenStack() -> [(owner: String, name: String)] {
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] ?? []
            return info.compactMap { entry in
                guard let owner = entry[kCGWindowOwnerName as String] as? String,
                      (entry[kCGWindowLayer as String] as? Int) == 0 || owner == "Summon"
                else { return nil }
                return (owner, (entry[kCGWindowName as String] as? String) ?? "")
            }
        }

        let libraryOpenAfter = NSApp.windows.contains { $0.isVisible && !($0 is SummonPanel) && !$0.title.isEmpty }
        line(libraryOpenAfter && !libraryOpenBefore
             ? "FAIL  summoning re-opened the library window"
             : "PASS  summoning did not re-open a closed library window")

        let stack = onScreenStack()
        line("front-to-back: " + stack.prefix(6).map { "\($0.owner)/\($0.name)" }.joined(separator: " | "))

        let summonIndices = stack.enumerated().filter { $0.element.owner == "Summon" }.map(\.offset)
        let otherAppIndex = stack.firstIndex { $0.owner != "Summon" }
        // The panel reports an empty window name; the library window carries the
        // title of whatever section is showing.
        let libraryIndex = stack.firstIndex { $0.owner == "Summon" && !$0.name.isEmpty }

        line("   app active: \(NSApp.isActive), was active before summon: \(wasActive)")
        if let libraryIndex, let otherAppIndex {
            line(libraryIndex < otherAppIndex
                 ? "FAIL  the library window sits in front of another app's window"
                 : "PASS  the library window stayed behind the app you were using")
        } else if libraryIndex == nil {
            line("····  no library window on screen to judge")
        } else {
            line("····  no other app's window on screen to compare against")
        }
        _ = summonIndices

        let panel = controller.debugPanel
        line("panel visible: \(panel?.isVisible == true)")
        line(panel?.isKeyWindow == true
             ? "PASS  the panel takes key focus, so typing reaches it"
             : "FAIL  the panel is not key — typing would go elsewhere")

        _ = libraryWindow

        // The decisive test: does typing actually reach the panel? isKeyWindow alone
        // does not prove keystrokes are routed here when the app is not active.
        model.query = ""
        try? await Task.sleep(for: .milliseconds(300))
        guard mayPostInput else {
            line("····  synthetic input skipped (set SUMMON_UIPROBE_INPUT=1 to enable)")
            try? report.write(toFile: "/tmp/summon-uiprobe.txt", atomically: true, encoding: .utf8)
            exit(0)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: down)?  // "a"
                .post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(600))
        line(model.query == "a"
             ? "PASS  typing reaches the panel without activating the app"
             : "FAIL  typing did not reach the panel (query is “\(model.query)”)")

        try? report.write(toFile: "/tmp/summon-uiprobe.txt", atomically: true, encoding: .utf8)
        exit(0)
    }
}
