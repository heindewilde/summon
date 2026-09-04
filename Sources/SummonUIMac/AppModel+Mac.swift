import AppKit
import SummonKit
import SummonUI

/// The AppKit half of `AppModel`.
///
/// `AppModel` itself is the cross-platform controller — search, folder scope, the
/// vault lifecycle, filing and tagging all mean the same thing on a phone. What
/// cannot follow it there is anything phrased in AppKit's vocabulary, and an
/// extension is enough to carry that: methods cross a module boundary freely, and it
/// is only stored properties that cannot.
extension AppModel {
    /// The field editor's path. Unmodified editing keys arrive as selectors.
    ///
    /// A `Selector` is the shape AppKit's `doCommandBy` hands over, so this is macOS
    /// by its signature rather than by its body — the key map it consults is pure data
    /// that an iPad's hardware keyboard will reach through `.onKeyPress` instead.
    @discardableResult
    public func routeFieldSelector(_ selector: Selector, fieldIsEmpty: Bool) -> Bool {
        guard let key = PanelKeyRouter.key(for: selector) else { return false }
        let modifiers = KeyModifiers(NSApp.currentEvent?.modifierFlags ?? [])
        guard let command = PanelKeyMap.command(for: KeyChord(key, modifiers),
                                                in: keyContext,
                                                queryIsEmpty: fieldIsEmpty,
                                                selectionIsFolder: selectionHasFolder) else { return false }
        perform(command)
        return true
    }
}
