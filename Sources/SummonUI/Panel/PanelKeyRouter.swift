import AppKit
import SummonKit
import SwiftUI

/// Live modifier state, on its own object.
///
/// This must not live on `AppModel`: every `PanelView` body reads several `AppModel`
/// properties, and `@Observable` invalidates a view when any property it read
/// changes — so holding ⌘ would re-render the whole result list sixty times a second.
/// `AppModel` holds this as a `let`, so reading `model.modifiers` is not an observed
/// access; only the footer reads `.held`, and only the footer redraws.
@MainActor
@Observable
public final class PanelModifierState {
    public private(set) var held: KeyModifiers = []

    public init() {}

    func set(_ new: KeyModifiers) {
        // Coalesced to the three that change a label. Without this, caps lock, fn and
        // the left/right variants each produce a redundant invalidation.
        let relevant = new.intersection([.command, .option, .shift])
        if relevant != held { held = relevant }
    }
}

/// Bridges AppKit key events to the pure key map.
///
/// Split along the line AppKit already draws: modified chords arrive through the
/// window's `performKeyEquivalent`, unmodified editing keys through the field
/// editor's `doCommandBy`. That split is what lets ⌘1–⌘9 and ⌘K work without the
/// panel ever fighting the search field over ordinary typing.
@MainActor
public final class PanelKeyRouter {
    private let model: AppModel
    private var flagsMonitor: Any?

    public init(model: AppModel) {
        self.model = model
    }

    // MARK: - Modified chords, from the window

    public func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard model.isPanelVisible, let chord = KeyChord(event: event) else { return false }
        return model.route(chord)
    }

    /// ⌘↑ / ⌘↓ are translated by the text system into these selectors reliably, which
    /// is a firmer contract than arrow-plus-command reaching `performKeyEquivalent`.
    static func key(for selector: Selector) -> KeyChord.Key? {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): .up
        case #selector(NSResponder.moveDown(_:)): .down
        case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): .pageUp
        case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): .pageDown
        case #selector(NSResponder.moveToBeginningOfDocument(_:)): .home
        case #selector(NSResponder.moveToEndOfDocument(_:)): .end
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): .enter
        case #selector(NSResponder.cancelOperation(_:)): .escape
        case #selector(NSResponder.insertTab(_:)): .tab
        case #selector(NSResponder.insertBacktab(_:)): .backTab
        case #selector(NSResponder.deleteBackward(_:)): .delete
        default: nil
        }
    }


    // MARK: - Live modifiers

    public func beginModifierTracking() {
        guard flagsMonitor == nil else { return }
        // Seed from the current state: modifiers already held when the panel appears
        // produce no flagsChanged of their own.
        model.modifiers.set(KeyModifiers(NSEvent.modifierFlags))

        let box = UncheckedBox(model.modifiers)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            // Local monitors are delivered on the main thread, which is what makes
            // assumeIsolated correct here. A Task hop would make the footer lag the key.
            MainActor.assumeIsolated {
                box.value.set(KeyModifiers(event.modifierFlags))
            }
            return event   // never swallow: the text system needs these
        }
    }

    public func endModifierTracking() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        model.modifiers.set([])
    }
}

/// The local-monitor closure is typed `@Sendable` by AppKit, so the main-actor state
/// it touches has to cross that boundary. Narrow and unwrapped only inside
/// `assumeIsolated`.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - AppKit adapters

public extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        self = result
    }
}

public extension KeyChord {
    init?(event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let key: Key
        switch Int(event.keyCode) {
        case 126: key = .up
        case 125: key = .down
        case 123: key = .left
        case 124: key = .right
        case 36, 76: key = .enter
        case 53: key = .escape
        case 48: key = modifiers.contains(.shift) ? .backTab : .tab
        case 51: key = .delete
        case 116: key = .pageUp
        case 121: key = .pageDown
        case 115: key = .home
        case 119: key = .end
        default:
            // charactersIgnoringModifiers so ⌥1 is still "1"; lowercased so ⇧⌘P and
            // ⌘P resolve to the same binding.
            guard let raw = event.charactersIgnoringModifiers?.lowercased(),
                  let character = raw.first, raw.count == 1 else { return nil }
            key = .character(character)
        }
        self.init(key, modifiers)
    }
}
