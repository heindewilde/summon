import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import SummonKit

/// Remembers which app you were in before the panel appeared, so content can be put
/// back exactly where your cursor was.
@MainActor
public final class FocusTracker {
    public private(set) var previousApp: NSRunningApplication?
    public private(set) var previousBundleID: String?

    public init() {}

    /// Must be called *before* the panel is shown, while the other app is still front.
    public func capture() {
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApp = front
        previousBundleID = front?.bundleIdentifier
    }

    public func clear() {
        previousApp = nil
        previousBundleID = nil
    }

    @discardableResult
    public func restoreFocus() -> Bool {
        guard let app = previousApp, !app.isTerminated else { return false }
        return app.activate(options: [])
    }
}

/// Puts content on the pasteboard and, when permitted, presses ⌘V for you.
@MainActor
public final class Inserter {
    public init() {}

    // MARK: - Accessibility

    /// Whether we may synthesise the paste keystroke. Never blocks; never prompts.
    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt. Call at the moment it would first help, not at launch.
    public static func requestAccessibility() {
        // The key is a global `var` in the C header, so read it under a nonisolated
        // shim rather than touching shared mutable state from an isolated context.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: kCFBooleanTrue as Any] as CFDictionary)
    }

    public static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Pasteboard

    /// Writes a payload to the general pasteboard.
    ///
    /// Rich text goes on alongside a plain-text fallback, so an app that cannot take
    /// RTF still gets something sensible rather than nothing.
    /// The pasteboard is a parameter so this can be exercised in tests without
    /// clobbering whatever the person running them had copied.
    public func writeToPasteboard(
        _ payload: InsertPayload,
        plainOnly: Bool = false,
        to pb: NSPasteboard = .general
    ) {
        pb.clearContents()

        // Everything goes on in a single `writeObjects` call. Mixing `writeObjects`
        // with `setData` silently drops the later flavours, because `setData` writes
        // to the first item rather than adding a representation to what was written.
        var objects: [NSPasteboardWriting] = []

        if let url = payload.fileURL {
            // URL first: Mail and Finder look for a file before anything else.
            objects.append(url as NSURL)
        }
        if let imageData = payload.imageData, let image = NSImage(data: imageData) {
            // An NSImage alongside the URL is what image editors and web forms want.
            objects.append(image)
        }

        let textItem = NSPasteboardItem()
        var hasText = false
        if let rtf = payload.rtf, !plainOnly {
            textItem.setData(rtf, forType: .rtf)
            hasText = true
        }
        if let text = payload.plainText, !text.isEmpty {
            textItem.setString(text, forType: .string)
            hasText = true
        }
        if hasText {
            // Text leads when there is no file, so a plain snippet pastes as text.
            payload.fileURL == nil ? objects.insert(textItem, at: 0) : objects.append(textItem)
        }

        guard !objects.isEmpty else { return }
        pb.writeObjects(objects)
    }

    public func currentClipboardText() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    // MARK: - Insertion

    /// The whole "summon moment": put it on the clipboard, give focus back, paste.
    @discardableResult
    public func insert(
        _ payload: InsertPayload,
        into tracker: FocusTracker,
        plainOnly: Bool = false,
        autoPaste: Bool = true
    ) async -> InsertOutcome {
        guard !payload.isEmpty else { return .failed("Nothing to insert.") }

        writeToPasteboard(payload, plainOnly: plainOnly)

        guard autoPaste, Inserter.hasAccessibility else {
            _ = tracker.restoreFocus()
            return .copiedOnly
        }
        guard tracker.previousApp != nil else { return .copiedOnly }

        let restored = tracker.restoreFocus()
        guard restored else { return .copiedOnly }

        // Give the target app a moment to actually take key focus. Without this the
        // keystroke lands before the app is ready and is silently dropped.
        try? await Task.sleep(for: .milliseconds(120))

        postCommandV()

        if let back = payload.cursorOffsetFromEnd, back > 0 {
            try? await Task.sleep(for: .milliseconds(60))
            postLeftArrow(times: min(back, 2000))
        }
        return .pasted
    }

    // MARK: - Synthetic keystrokes

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Do not let a physically-held modifier (⌥ is often still down right after
        // ⌥Space) turn our ⌘V into ⌥⌘V, which means "paste and match style".
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postLeftArrow(times: Int) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let left = CGKeyCode(kVK_LeftArrow)
        for _ in 0..<times {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: left, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: left, keyDown: false)
            else { return }
            down.flags = []
            up.flags = []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Synthesises ⌘C in the frontmost app and returns whatever landed on the
    /// pasteboard. Used by the save-selection hotkey outside Finder.
    public func copyCurrentSelection() async -> NSPasteboard.PasteboardType? {
        guard Inserter.hasAccessibility else { return nil }
        let pb = NSPasteboard.general
        let before = pb.changeCount

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return nil }
        let c = CGKeyCode(kVK_ANSI_C)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: c, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: c, keyDown: false)
        else { return nil }
        down.flags = .maskCommand
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        // Poll briefly rather than guessing a single fixed delay.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if pb.changeCount != before { break }
        }
        guard pb.changeCount != before else { return nil }
        if pb.data(forType: .png) != nil { return .png }
        if pb.data(forType: .tiff) != nil { return .tiff }
        if pb.data(forType: .rtf) != nil { return .rtf }
        if pb.string(forType: .string) != nil { return .string }
        return nil
    }
}
