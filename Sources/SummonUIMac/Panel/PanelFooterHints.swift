import SummonKit
import SwiftUI
import SummonUI

/// The footer's key hints, which change under your fingers.
///
/// Extracted into its own view for one reason: it is the only thing that reads
/// `PanelModifierState.held`. Under Observation a view is invalidated by the
/// properties *it* read, so holding ⌘ redraws this 40pt strip and leaves the result
/// list alone. Put the same state on `AppModel` and every modifier press would
/// re-render the whole panel.
public struct PanelFooterHints: View {
    let modifiers: PanelModifierState
    let defaultLabel: String
    let canOpen: Bool
    let canDrillIn: Bool

    public init(modifiers: PanelModifierState, defaultLabel: String,
                canOpen: Bool, canDrillIn: Bool) {
        self.modifiers = modifiers
        self.defaultLabel = defaultLabel
        self.canOpen = canOpen
        self.canDrillIn = canDrillIn
    }

    public var body: some View {
        HStack(spacing: Theme.Space.l) {
            // While a modifier is down, say what ↩ does *now* rather than listing
            // every variant at once. This is how the shortcuts get learned without a
            // help screen.
            switch held {
            case .command: KeyHint("⌘↩", "Copy")
            case .option where canOpen: KeyHint("⌥↩", "Open")
            case .option: KeyHint("↩", defaultLabel)
            case .shift: KeyHint("⇧↩", "Paste plain")
            case .none:
                KeyHint("↩", defaultLabel)
                if canDrillIn { KeyHint("⇥", "Open folder") }
            }
            KeyHint("⌘K", "Actions")
        }
        .animation(nil, value: modifiers.held)
    }

    private enum Held { case command, option, shift, none }

    private var held: Held {
        let flags = modifiers.held
        if flags.contains(.command) { return .command }
        if flags.contains(.option) { return .option }
        if flags.contains(.shift) { return .shift }
        return .none
    }
}
