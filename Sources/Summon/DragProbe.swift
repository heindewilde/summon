import AppKit
import SummonKit
import SummonUI
import SummonUIMac

/// Drives a real drag from an item row onto a folder row, and reports where it got to.
///
/// Dropping an item on a folder is the one behaviour in this app that no unit test
/// can reach: it depends on what SwiftUI hands the drop delegate, which only exists
/// during a genuine drag session. `SUMMON_DRAGPROBE=1`.
///
/// It reports the *stages* rather than a single pass/fail, because "it doesn't work"
/// has three quite different causes — the row never became a drop target, the target
/// engaged but the payload was unreadable, or the move itself was refused — and
/// guessing between them is how an afternoon disappears.
@MainActor
enum DragProbe {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["SUMMON_DRAGPROBE"] == "1" }

    /// How long the machine has been left alone.
    ///
    /// This probe drives the pointer for the better part of a minute. Run while
    /// somebody is actually working, it fights them for the mouse — which both ruins
    /// the result and is plainly rude. It waits for the machine to be idle first, and
    /// gives up rather than barging in.
    private static var secondsIdle: Double {
        [CGEventType.mouseMoved, .leftMouseDown, .keyDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    private static func waitUntilIdle(_ line: (String) -> Void) async -> Bool {
        let required = Double(ProcessInfo.processInfo.environment["SUMMON_DRAGPROBE_IDLE"] ?? "4") ?? 4
        for _ in 0..<60 {
            if secondsIdle >= required { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        line("SKIP  the machine is in use — not taking the pointer away from someone")
        return false
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private static func label(_ element: AXUIElement) -> String {
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

    private static func walk(_ element: AXUIElement, depth: Int = 0, into found: inout [AXUIElement]) {
        guard depth < 24 else { return }
        for child in children(element) {
            found.append(child)
            walk(child, depth: depth + 1, into: &found)
        }
    }

    /// Whether a click at `point` would reach this process.
    ///
    /// Matched on pid rather than on the owner's name: a second copy of Summon
    /// running against the real library is still called "Summon", and posting events
    /// into somebody's actual data would be the same mistake with a nicer name on it.
    private static func ownsPoint(_ point: CGPoint) -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32
            else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(point) { return pid == me }
        }
        return false
    }

    /// The frontmost ordinary window, as the window server sees it.
    private static func frontWindow() -> (pid: Int32, name: String)? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32 else { continue }
            return (pid, (entry[kCGWindowOwnerName as String] as? String) ?? "?")
        }
        return nil
    }

    /// Brings the library window forward and waits until it really is in front.
    private static func comeForward(_ line: (String) -> Void) async -> Bool {
        NSApp.setActivationPolicy(.regular)
        let me = ProcessInfo.processInfo.processIdentifier
        for attempt in 1...20 {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.windows.first { $0.isVisible && !($0 is SummonPanel) }?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            if frontWindow()?.pid == me { return true }
            if attempt == 1 || attempt == 20 {
                line("  attempt \(attempt): active=\(NSApp.isActive) "
                     + "front=\(frontWindow().map { "\($0.name)#\($0.pid)" } ?? "none") "
                     + "windows=\(NSApp.windows.filter(\.isVisible).map { $0.title.isEmpty ? "(untitled)" : $0.title })")
            }
        }
        return false
    }

    /// Posts a genuine drag between two points, stepped so AppKit starts a session.
    private static func drag(from start: CGPoint, to end: CGPoint,
                             whileDragging: () -> Void = {}) async {
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        // Stepped, not teleported: AppKit only starts a drag session once the pointer
        // has moved past a threshold, and one jump to the destination reads as a click.
        for step in 1...30 {
            let t = CGFloat(step) / 30
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                    mouseCursorPosition: CGPoint(x: start.x + (end.x - start.x) * t,
                                                 y: start.y + (end.y - start.y) * t),
                    mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(30))
            whileDragging()
        }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .seconds(2))
    }

    /// Every element in the library window, re-read: the tree changes as the
    /// selection does, so a stale walk points at rows that have moved.
    private static func elements() -> [AXUIElement] {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let windows = (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
        guard let library = windows.first(where: { label($0).contains("Items") })
                ?? windows.first else { return [] }
        var found: [AXUIElement] = []
        walk(library, into: &found)
        return found
    }

    /// The centre of the first element whose label contains `text` and whose box fits
    /// the column being looked in.
    private static func point(for text: String, sidebar: Bool) -> CGPoint? {
        for element in elements() {
            guard !text.isEmpty, label(element).contains(text),
                  let box = frame(of: element), box.height < 80 else { continue }
            let matchesColumn = sidebar ? box.width < 320 : box.width > 250
            if matchesColumn { return CGPoint(x: box.midX, y: box.midY) }
        }
        return nil
    }

    static func run() async -> Never {
        var report = ""
        var failures = 0
        func line(_ text: String) { report += text + "\n"; print(text) }
        func check(_ name: String, _ passed: Bool, detail: String = "") {
            if !passed { failures += 1 }
            line("\(passed ? "PASS" : "FAIL")  \(name)" + (detail.isEmpty ? "" : " — \(detail)"))
        }
        func finish() -> Never {
            line(failures == 0 ? "=== all drag paths work ===" : "=== \(failures) failed ===")
            try? report.write(toFile: "/tmp/summon-dragprobe.txt", atomically: true, encoding: .utf8)
            exit(failures == 0 ? 0 : 1)
        }

        let model = Services.model
        model.isHarness = true
        await model.seedStarterLibraryIfEmpty()
        model.store.refresh()
        model.sidebarSelection = .all
        model.showMainWindowHandler?()
        try? await Task.sleep(for: .seconds(2))

        guard AXIsProcessTrusted() else {
            line("SKIP  Accessibility is not granted, so rows cannot be located")
            try? report.write(toFile: "/tmp/summon-dragprobe.txt", atomically: true, encoding: .utf8)
            exit(2)
        }
        guard await waitUntilIdle(line) else {
            try? report.write(toFile: "/tmp/summon-dragprobe.txt", atomically: true, encoding: .utf8)
            exit(2)
        }
        guard await comeForward(line) else {
            line("SKIP  could not bring the library window to the front — refusing to post")
            line("      events that would land in whatever app is there instead")
            try? report.write(toFile: "/tmp/summon-dragprobe.txt", atomically: true, encoding: .utf8)
            exit(2)
        }

        var trace: [String] = []
        model.dropTrace = { trace.append($0) }
        func showTrace() { for entry in trace { line("      · \(entry)") }; trace = [] }


        // MARK: An item onto a folder
        //
        // The behaviour that was broken: the row engaged, the cargo was recognised,
        // and then the id could not be read back off the drag, so nothing moved.
        let folders = model.sidebarFolderRows
        if let destination = folders.first,
           let subject = model.visibleItems.first(where: { !$0.isLocked && $0.folderID != destination.id }),
           let from = point(for: subject.title, sidebar: false),
           let to = point(for: destination.name, sidebar: true),
           ownsPoint(from), ownsPoint(to) {
            line("· dragging “\(subject.title)” onto folder “\(destination.name)”")
            var sawIndicator = false
            await drag(from: from, to: to) { if model.folderDropTarget != nil { sawIndicator = true } }
            if !sawIndicator, let retryFrom = point(for: subject.title, sidebar: false) {
                line("  (no drag session started; retrying once)")
                await drag(from: retryFrom, to: to) {
                    if model.folderDropTarget != nil { sawIndicator = true }
                }
            }
            showTrace()
            check("the folder row engages as a drop target", sawIndicator)
            check("an item dropped on a folder is filed there",
                  model.store.item(id: subject.id)?.folder?.id == destination.id,
                  detail: model.store.item(id: subject.id)?.folder?.name ?? "no folder")
            check("the indicator clears when the drag ends", model.folderDropTarget == nil)
        } else {
            check("an item dropped on a folder is filed there", false, detail: "could not locate the rows")
        }

        // MARK: A folder onto another folder
        //
        // Worth its own case because the identifier route changed underneath it too:
        // folder drags used to travel as prefixed plain text.
        model.sidebarSelection = .all
        try? await Task.sleep(for: .milliseconds(500))
        let tree = model.sidebarFolderRows
        if let child = tree.first(where: { $0.depth == 0 }),
           let parent = tree.first(where: { $0.depth == 0 && $0.id != child.id }),
           let from = point(for: child.name, sidebar: true),
           let to = point(for: parent.name, sidebar: true),
           ownsPoint(from), ownsPoint(to) {
            line("· dragging folder “\(child.name)” onto folder “\(parent.name)”")
            await drag(from: from, to: to)
            showTrace()
            let moved = model.store.folder(id: child.id)?.parent?.id
            check("a folder dropped on a folder nests inside it",
                  moved == parent.id,
                  detail: model.store.folder(id: child.id)?.parent?.name ?? "still at the top level")
            // Put it back, so the next run starts from the same shape.
            if let folder = model.store.folder(id: child.id) { model.store.moveFolder(folder, under: nil) }
        } else {
            check("a folder dropped on a folder nests inside it", false, detail: "could not locate the rows")
        }

        // MARK: An item onto another item, inside a folder
        model.store.refresh()
        if let folder = model.sidebarFolderRows.first(where: { $0.itemCount >= 2 }) {
            model.sidebarSelection = .folder(folder.id)
            try? await Task.sleep(for: .seconds(1))
            let order = model.itemsForSidebar()
            if order.count >= 2,
               let from = point(for: order[0].title, sidebar: false),
               let to = point(for: order[1].title, sidebar: false),
               ownsPoint(from), ownsPoint(to) {
                line("· reordering “\(order[0].title)” below “\(order[1].title)” in “\(folder.name)”")
                var sawLine = false
                // Aim just past the second row's midpoint, so the drop reads as "after".
                await drag(from: from, to: CGPoint(x: to.x, y: to.y + 12)) {
                    if model.itemDropTarget != nil { sawLine = true }
                }
                showTrace()
                check("the item list shows an insertion line", sawLine)
                let after = model.itemsForSidebar().map(\.id)
                check("dragging an item past another reorders it",
                      after.first == order[1].id,
                      detail: model.itemsForSidebar().map(\.title).joined(separator: ", "))
                check("the insertion line clears when the drag ends", model.itemDropTarget == nil)
            } else {
                check("dragging an item past another reorders it", false, detail: "could not locate the rows")
            }
        } else {
            check("dragging an item past another reorders it", false, detail: "no folder with two items")
        }

        finish()
    }
}
