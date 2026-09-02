import AppKit
import SwiftUI
import SummonKit
import SummonUI

/// The floating summon window.
///
/// A `.nonactivatingPanel` that can still become key — which is what lets you type
/// into it without the panel stealing the *document* focus of the app underneath.
/// The app is activated deliberately, after the previously-frontmost app has already
/// been recorded, so focus can be handed straight back on insert.
final class SummonPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape must close the panel even when a text field has focus. Routed through
    /// `AppModel.escape()` so it pops exactly one level rather than dismissing
    /// outright — the action menu and a folder scope are levels above the panel.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Modified chords are claimed here, before the responder chain and before the
    /// main menu — which is what lets ⌘K mean Actions in the panel. Everything the
    /// key map declines returns false, so ⌘C, ⌘V, ⌘A and ⌘Z keep working in the
    /// search field.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyRouter?.handleKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    var onCancel: (() -> Void)?
    var keyRouter: PanelKeyRouter?
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: SummonPanel?
    private let model: AppModel
    private let router: PanelKeyRouter

    init(model: AppModel) {
        self.model = model
        self.router = PanelKeyRouter(model: model)
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Exposed only for the runtime self-test, which asserts the panel's window
    /// configuration is what makes the summon-and-paste sequence work.
    var debugPanel: SummonPanel? { panel }

    func toggle() {
        if isVisible { hide() } else { model.summon() }
    }

    /// Builds the window and its hosting view ahead of the first summon, and forces a
    /// layout pass, so that cost is not paid inline on the first ⌥Space of a session.
    ///
    /// Deliberately *not* `orderFrontRegardless()` at `alphaValue = 0`: that touches
    /// the window server and interacts badly with `.transient` in the collection
    /// behaviour. This does not eliminate SwiftUI's first *display* pass — only a real
    /// on-screen appearance does that — so cold and warm summons are reported
    /// separately rather than pretending they are the same number.
    func prewarm() {
        guard panel == nil else { return }
        let panel = makePanel()
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    /// Puts the panel on screen for a screenshot without activating the app or taking
    /// key focus, so a capture cannot interrupt what someone is doing — and a stray
    /// keystroke cannot reach the panel and paste into their frontmost app.
    /// `screencapture -l` does not require the window to be key.
    func showForCapture() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.keyRouter = router
        router.beginModifierTracking()

        position(panel)

        // Activation is unavoidable: a .nonactivatingPanel only takes key focus while
        // the app is already active, so without this, typing goes to whatever app you
        // came from. Measured, not assumed — see UIProbe.
        //
        // The cost is that activating raises every window the app owns, which dragged
        // an open library window to the front on top of your work each time you
        // summoned. So the library is sent straight back behind the other apps'
        // windows, leaving only the panel in front.
        // Dropping below the normal level is what actually keeps them down: window
        // level orders across applications, whereas order(.below:) only reshuffles
        // this app's own list. Restored in hide().
        loweredWindows = NSApp.windows.filter { $0 !== panel && $0.isVisible && !$0.title.isEmpty }
        for window in loweredWindows {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        }
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        router.endModifierTracking()
        panel?.orderOut(nil)
        for window in loweredWindows { window.level = .normal }
        loweredWindows = []
    }

    /// Windows pushed below normal level while the panel is up.
    private var loweredWindows: [NSWindow] = []

    private func makePanel() -> SummonPanel {
        let panel = SummonPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: PanelView.height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.model.escape() }

        let host = NSHostingView(rootView: PanelView(model: model))
        host.frame = panel.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// Centred horizontally and set high on the screen the pointer is on — where the
    /// eye already is, rather than dead centre.
    private func position(_ panel: SummonPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let x = frame.midX - PanelView.width / 2
        let y = frame.maxY - PanelView.height - frame.height * 0.16
        panel.setFrame(
            NSRect(x: x.rounded(), y: max(frame.minY + 40, y).rounded(),
                   width: PanelView.width, height: PanelView.height),
            display: false
        )
    }

    // Clicking away is a dismissal — the panel should never linger.
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        model.dismissPanel()
    }
}
