import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI
import SummonKit
import SummonMacApp
import SummonUI
import SummonUIMac
import SummonKitMac

/// End-to-end verification of the auto-paste path — the one sequence that cannot be
/// unit tested, because it depends on a real Accessibility grant, real focus changes
/// and real synthesised keystrokes landing in another app.
///
/// Opens a scratch document in TextEdit, summons a snippet into it, then reads the
/// result back out through the Accessibility API to confirm what actually arrived.
/// Activated with `SUMMON_PASTETEST=1`; writes its report to `SUMMON_TEST_LOG`.
@MainActor
enum PasteTest {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["SUMMON_PASTETEST"] == "1"
    }

    private static var report: [String] = []
    private static var failures = 0

    private static func check(_ label: String, _ ok: Bool, detail: String = "") {
        if !ok { failures += 1 }
        report.append("  \(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    private static func info(_ label: String, _ value: String) {
        report.append("  ····  \(label): \(value)")
    }

    private static func flush() {
        let text = report.joined(separator: "\n")
        if let path = ProcessInfo.processInfo.environment["SUMMON_TEST_LOG"] {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        print(text)
    }

    /// ⌘ plus one key, into whatever is frontmost. Only ever used on the document
    /// this test opened itself, after the frontmost check above.
    private static func postCommandKey(_ key: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Empties the scratch document, so TextEdit quits without a save prompt.
    private static func tidyUp(app: NSRunningApplication, target: URL) async {
        postCommandKey(kVK_ANSI_A)
        try? await Task.sleep(for: .milliseconds(200))
        if let source = CGEventSource(stateID: .combinedSessionState),
           let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(200))
        postCommandKey(kVK_ANSI_S)
        try? await Task.sleep(for: .milliseconds(600))
        app.terminate()
        try? FileManager.default.removeItem(at: target)
    }

    static func run() async {
        let model = Services.model
        report.append("\n=== Auto-paste round trip ===")
        info("Accessibility granted", Inserter.hasAccessibility ? "yes" : "NO")

        guard Inserter.hasAccessibility else {
            check("Accessibility is granted to Summon", false,
                  detail: "cannot verify the paste path without it")
            flush()
            exit(1)
        }

        await model.seedStarterLibraryIfEmpty()
        try? await Task.sleep(for: .seconds(2))
        model.store.refresh()

        // A scratch document to paste into.
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "summon-paste-target.txt")
        try? "".write(to: target, atomically: true, encoding: .utf8)

        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        guard let app = try? await NSWorkspace.shared.open([target], withApplicationAt: textEdit,
                                                           configuration: config) else {
            check("TextEdit opens the scratch document", false)
            flush()
            exit(1)
        }
        // Wait for TextEdit to genuinely come forward. A cold launch can take several
        // seconds, and proceeding early would mean synthesising ⌘V into whatever app
        // happens to be in front — someone else's document.
        var frontmost: String?
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(400))
            app.activate()
            frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if frontmost == "com.apple.TextEdit" { break }
        }
        check("TextEdit is frontmost", frontmost == "com.apple.TextEdit",
              detail: frontmost ?? "none")

        // This is the sequence the hot key performs: remember who was in front,
        // show the panel, then hand focus back and paste.
        model.focus.capture()
        info("Captured frontmost app", model.focus.previousBundleID ?? "none")
        check("The app in front is remembered before the panel appears",
              model.focus.previousBundleID == "com.apple.TextEdit")

        // Hard stop: never synthesise a paste into an app this test did not open.
        guard model.focus.previousBundleID == "com.apple.TextEdit" else {
            check("Refusing to paste into an unrelated app", false,
                  detail: "target was \(model.focus.previousBundleID ?? "unknown"), not TextEdit")
            app.terminate()
            try? FileManager.default.removeItem(at: target)
            flush()
            exit(1)
        }

        model.summon()
        try? await Task.sleep(for: .milliseconds(700))

        guard let snippet = model.store.snapshots.first(where: {
            $0.kind == .text && $0.title == "New enquiry — first reply"
        }) ?? model.store.snapshots.first(where: { $0.kind == .text }) else {
            check("A snippet is available to insert", false)
            flush()
            exit(1)
        }

        let values = ["first_name": "Marieke", "project": "the rebrand"]
        guard let payload = model.store.payload(for: snippet.id, fieldValues: values) else {
            check("The snippet resolves to a payload", false)
            flush()
            exit(1)
        }
        let expected = payload.plainText ?? ""
        let caretBack = payload.cursorOffsetFromEnd

        model.dismissPanel()
        let outcome = await model.inserter.insert(payload, into: model.focus, plainOnly: false, autoPaste: true)
        check("Insert reports a real paste, not a clipboard fallback", outcome == .pasted,
              detail: "\(outcome)")

        try? await Task.sleep(for: .seconds(1))

        // Read back what actually landed. Preferably through the Accessibility API,
        // which also reports where the caret ended up — but a *sandboxed* build may
        // not inspect another app's UI, even with the Accessibility grant that lets
        // it post the keystroke. (Posting and inspecting are separate powers; only
        // the second is denied.) So fall back to saving the document and reading the
        // file, which tests the same thing minus the caret.
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        let focused: AXUIElement? = (focusedRef.flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        })
        info("Read back via", focused == nil ? "saving the file (the sandbox hides other apps' UI)" : "the Accessibility API")

        let landed: String
        if let focused {
            var valueRef: CFTypeRef?
            AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef)
            landed = (valueRef as? String) ?? ""
        } else {
            postCommandKey(kVK_ANSI_S)
            try? await Task.sleep(for: .seconds(2))
            landed = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
        }

        check("Text arrived in TextEdit", !landed.isEmpty,
              detail: "\(landed.count) characters")
        check("The whole snippet arrived intact", landed.contains(expected),
              detail: String(landed.prefix(46)).replacingOccurrences(of: "\n", with: " ") + "…")
        check("Fill-in values were substituted", landed.contains("Marieke") && landed.contains("the rebrand"))
        check("No unresolved placeholders were pasted", !landed.contains("{{"))

        // And the caret: {{cursor}} should have positioned it, not left it at the end.
        guard let focused else {
            info("Caret position", "not checkable under the sandbox")
            await tidyUp(app: app, target: target)
            report.append("=== \(report.filter { $0.contains("PASS") }.count) passed, \(failures) failed ===")
            flush()
            exit(failures == 0 ? 0 : 1)
        }
        var rangeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        var range = CFRange()
        if let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)
        }
        if let caretBack {
            let expectedLocation = landed.utf16.count - caretBack
            check("The caret landed where {{cursor}} was",
                  abs(range.location - expectedLocation) <= 1,
                  detail: "caret at \(range.location), expected \(expectedLocation)")
        } else {
            info("Snippet had no {{cursor}} token", "caret check skipped")
        }

        // Leave the document empty so TextEdit quits without a save prompt.
        AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, "" as CFTypeRef)
        try? await Task.sleep(for: .milliseconds(400))
        await tidyUp(app: app, target: target)

        report.append("=== \(report.filter { $0.contains("PASS") }.count) passed, \(failures) failed ===")
        flush()
        exit(failures == 0 ? 0 : 1)
    }
}
