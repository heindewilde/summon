import AppKit
import SummonKit

/// The Accessibility grant, read once and cached.
///
/// `AXIsProcessTrusted()` is a TCC round trip. `PanelView.body` called it twice — once
/// for the footer note and once to decide the ↩ label — so it ran on every keystroke.
/// The answer only changes when the user visits System Settings, which always means
/// leaving and returning to the app.
@MainActor
@Observable
public final class AccessibilityStatus {
    public private(set) var isTrusted: Bool

    public init() {
        isTrusted = Inserter.hasAccessibility
    }

    public func refresh() {
        let now = Inserter.hasAccessibility
        if now != isTrusted { isTrusted = now }
    }
}
