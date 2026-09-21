import Observation

/// The Accessibility grant, read once and cached.
///
/// `AXIsProcessTrusted()` is a TCC round trip. `PanelView.body` called it twice — once
/// for the footer note and once to decide the ↩ label — so it ran on every keystroke.
/// The answer only changes when the user visits System Settings, which always means
/// leaving and returning to the app.
///
/// The probe is injected rather than called directly, because `Inserter` lives in the
/// macOS target and this does not. The default answers `true`: on a platform with no
/// such permission to grant, "not trusted" would be a permanently false warning rather
/// than an honest one.
@MainActor
@Observable
public final class AccessibilityStatus {
    @ObservationIgnored private let probe: @MainActor () -> Bool
    public private(set) var isTrusted: Bool

    public init(probe: @escaping @MainActor () -> Bool = { true }) {
        self.probe = probe
        isTrusted = probe()
    }

    public func refresh() {
        let now = probe()
        if now != isTrusted { isTrusted = now }
    }
}
