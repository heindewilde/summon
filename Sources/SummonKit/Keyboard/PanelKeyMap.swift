import Foundation

/// How activating an item delivers it. Lives here rather than on the view model
/// because the key map has to name it, and the key map must stay free of UI.
public enum ActivationStyle: Sendable, Equatable {
    case paste, copy, open, plainPaste
}

/// Which surface currently owns the keyboard.
public enum PanelContext: Sendable, Equatable {
    case results
    case actionMenu
    case fill
    case unlock
}

/// Everything a key press can ask the panel to do.
public enum PanelCommand: Sendable, Equatable {
    case move(Int)
    case selectFirst
    case selectLast
    case activate(ActivationStyle)
    /// ⌘1–⌘9. Zero-based.
    case activateIndex(Int)
    case toggleActionMenu
    case runSelectedAction
    /// Pops exactly one level: menu → mode → folder → panel.
    case escape
    case drillIn
    case drillOut
    case nextField
    case previousField
    case action(PanelActionID)
}

/// The actions offered for an item, in ⌘K and by direct shortcut.
public enum PanelActionID: String, CaseIterable, Sendable {
    case paste, pastePlain, copy, open, reveal, rename, move, addTag,
         togglePin, toggleSensitive, delete

    public var title: String {
        switch self {
        case .paste: "Paste"
        case .pastePlain: "Paste as Plain Text"
        case .copy: "Copy"
        case .open: "Open"
        case .reveal: "Reveal in Finder"
        case .rename: "Rename"
        case .move: "Move to Folder…"
        case .addTag: "Add Tag…"
        case .togglePin: "Pin"
        case .toggleSensitive: "Mark Sensitive"
        case .delete: "Delete"
        }
    }

    public var symbolName: String {
        switch self {
        case .paste: "arrow.down.doc"
        case .pastePlain: "doc.plaintext"
        case .copy: "doc.on.doc"
        case .open: "arrow.up.forward.app"
        case .reveal: "folder"
        case .rename: "pencil"
        case .move: "folder.badge.plus"
        case .addTag: "tag"
        case .togglePin: "pin"
        case .toggleSensitive: "lock"
        case .delete: "trash"
        }
    }

    public var isDestructive: Bool { self == .delete }
}

/// The single source of truth for the keyboard model.
///
/// Pure and AppKit-free, so every binding is asserted in the test suite rather than
/// discovered by pressing keys — which is how the panel came to draw ⌘1–⌘9 on every
/// row with nothing behind them.
public enum PanelKeyMap {

    public static func chord(for action: PanelActionID) -> KeyChord? {
        switch action {
        case .paste: KeyChord(.enter)
        case .pastePlain: KeyChord(.enter, .shift)
        case .copy: KeyChord(.enter, .command)
        case .open: KeyChord(.enter, .option)
        case .reveal: KeyChord(.character("r"), .command)
        case .togglePin: KeyChord(.character("p"), .command)
        case .delete: KeyChord(.delete, .command)
        case .rename, .move, .addTag, .toggleSensitive: nil
        }
    }

    /// What ⌘K offers. Order is the order it lists them.
    public static func actions(isBlobBacked: Bool, isLocked: Bool) -> [PanelActionID] {
        guard !isLocked else { return [.togglePin, .toggleSensitive, .rename, .delete] }
        var actions: [PanelActionID] = [.paste, .pastePlain, .copy]
        if isBlobBacked { actions += [.open, .reveal] }
        actions += [.rename, .move, .addTag, .togglePin, .toggleSensitive, .delete]
        return actions
    }

    /// Resolves a key press against the current context.
    ///
    /// Returns nil when the panel should not claim the key, so it falls through to the
    /// text field — that is what keeps ⌘C, ⌘V, ⌘A and ordinary typing working.
    public static func command(for chord: KeyChord,
                               in context: PanelContext,
                               queryIsEmpty: Bool,
                               selectionIsFolder: Bool) -> PanelCommand? {
        // Escape means the same thing everywhere: go back exactly one level.
        if chord == KeyChord(.escape) { return .escape }

        switch context {
        case .results:
            return resultsCommand(chord, queryIsEmpty: queryIsEmpty, selectionIsFolder: selectionIsFolder)
        case .actionMenu:
            return actionMenuCommand(chord)
        case .fill:
            return fillCommand(chord)
        case .unlock:
            return chord == KeyChord(.enter) ? .activate(.paste) : nil
        }
    }

    private static func resultsCommand(_ chord: KeyChord,
                                       queryIsEmpty: Bool,
                                       selectionIsFolder: Bool) -> PanelCommand? {
        switch (chord.key, chord.modifiers) {
        case (.up, []): return .move(-1)
        case (.down, []): return .move(1)
        case (.pageUp, []): return .move(-8)
        case (.pageDown, []): return .move(8)
        case (.up, .command), (.home, []): return .selectFirst
        case (.down, .command), (.end, []): return .selectLast

        case (.enter, let modifiers):
            if modifiers.contains(.command) { return .activate(.copy) }
            if modifiers.contains(.option) { return .activate(.open) }
            if modifiers.contains(.shift) { return .activate(.plainPaste) }
            return .activate(.paste)

        case (.character("k"), .command): return .toggleActionMenu
        case (.character("p"), .command): return .action(.togglePin)
        case (.character("r"), .command): return .action(.reveal)
        case (.delete, .command): return .action(.delete)

        // Only claim ⇥ when there is somewhere to go, so it stays available to the
        // field otherwise.
        case (.tab, []): return selectionIsFolder ? .drillIn : nil
        // ⌫ on an empty query walks back up; with text typed it is an ordinary edit.
        case (.delete, []): return queryIsEmpty ? .drillOut : nil

        case (.character(let c), .command):
            guard let digit = c.wholeNumberValue, (1...9).contains(digit) else { return nil }
            return .activateIndex(digit - 1)

        default: return nil
        }
    }

    private static func actionMenuCommand(_ chord: KeyChord) -> PanelCommand? {
        switch (chord.key, chord.modifiers) {
        case (.up, []): return .move(-1)
        case (.down, []): return .move(1)
        case (.enter, []): return .runSelectedAction
        case (.character("k"), .command): return .toggleActionMenu
        default: return nil
        }
    }

    private static func fillCommand(_ chord: KeyChord) -> PanelCommand? {
        switch (chord.key, chord.modifiers) {
        case (.tab, []): return .nextField
        case (.backTab, []), (.tab, .shift): return .previousField
        case (.enter, []): return .activate(.paste)
        default: return nil
        }
    }
}
