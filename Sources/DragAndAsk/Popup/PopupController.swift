import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private var panel: NSPanel?
    private let viewModel = PopupViewModel()

    func show(selection: String, sourceFile: String, pdfURL: URL?, errorMessage: String? = nil) {
        ensurePanel()
        viewModel.start(selection: selection, sourceFile: sourceFile, pdfURL: pdfURL, errorMessage: errorMessage)
        position()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        viewModel.reset()
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.standardWindowButton(.closeButton)?.target = self
        p.standardWindowButton(.closeButton)?.action = #selector(handleClose)

        let host = NSHostingController(rootView: PopupView(vm: viewModel, onClose: { [weak self] in self?.hide() }))
        p.contentViewController = host
        panel = p
    }

    @objc private func handleClose() {
        hide()
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 + visible.height * 0.18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// A panel subclass that can become key even though it's a nonactivating panel.
/// Necessary so the ESC key handler and the follow-up text field receive events.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
