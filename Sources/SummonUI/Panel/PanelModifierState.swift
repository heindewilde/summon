import Observation
import SummonKit

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

    public func set(_ new: KeyModifiers) {
        // Coalesced to the three that change a label. Without this, caps lock, fn and
        // the left/right variants each produce a redundant invalidation.
        let relevant = new.intersection([.command, .option, .shift])
        if relevant != held { held = relevant }
    }
}
