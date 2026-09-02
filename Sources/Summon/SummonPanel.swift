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

    /// Escape must close the panel even when a text field has focus.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    var onCancel: (() -> Void)?
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: SummonPanel?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Exposed only for the runtime self-test, which asserts the panel's window
    /// configuration is what makes the summon-and-paste sequence work.
    var debugPanel: SummonPanel? { panel }

    func toggle() {
        if isVisible { hide() } else { model.summon() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        position(panel)
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

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
        panel.onCancel = { [weak self] in self?.model.dismissPanel() }

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
