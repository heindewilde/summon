import Foundation

/// The modifier keys Summon cares about, free of AppKit so the key model can be
/// tested without a window.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)

    /// Rendered in the order macOS renders them.
    public var display: String {
        var out = ""
        if contains(.control) { out += "⌃" }
        if contains(.option) { out += "⌥" }
        if contains(.shift) { out += "⇧" }
        if contains(.command) { out += "⌘" }
        return out
    }
}

public struct KeyChord: Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case character(Character)
        case up, down, left, right
        case enter, escape, tab, backTab, delete
        case pageUp, pageDown, home, end

        var display: String {
            switch self {
            case .character(let c): String(c).uppercased()
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            case .enter: "↩"
            case .escape: "⎋"
            case .tab: "⇥"
            case .backTab: "⇧⇥"
            case .delete: "⌫"
            case .pageUp: "⇞"
            case .pageDown: "⇟"
            case .home: "↖"
            case .end: "↘"
            }
        }
    }

    public var key: Key
    public var modifiers: KeyModifiers

    public init(_ key: Key, _ modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// What the footer and the ⌘K list print. One source, so a hint can never drift
    /// from the binding it describes.
    public var display: String { modifiers.display + key.display }
}
