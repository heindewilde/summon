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

    /// Every descendant, with its depth.
    private static func walk(_ element: AXUIElement, depth: Int = 0, into found: inout [(Int, AXUIElement)]) {
        guard depth < 24 else { return }
        for child in children(element) {
            found.append((depth, child))
            walk(child, depth: depth + 1, into: &found)
        }
    }

    static func run() async -> Never {
        let model = Services.model
        await model.seedStarterLibraryIfEmpty()
        try? await Task.sleep(for: .seconds(2))
        model.store.refresh()
        model.sidebarSelection = .all
        model.mainSelection = nil
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

        // The decisive test: put the pointer on a row and click it. Everything above
        // only says the row exists.
        let before = model.mainSelection
        var clicked = false
        for (_, element) in found where role(element) == "AXRow" {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
            else { continue }

            var origin = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            guard size.width > 250, size.height > 20 else { continue }   // an item row, not a sidebar row

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

        try? report.write(toFile: "/tmp/summon-uiprobe.txt", atomically: true, encoding: .utf8)
        exit(0)
    }
}
