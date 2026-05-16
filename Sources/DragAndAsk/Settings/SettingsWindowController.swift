import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingController(rootView: SettingsView())
        host.sizingOptions = []  // don't let SwiftUI shrink the window
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 780),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "drag & ask · Settings"
        w.contentViewController = host
        w.setContentSize(NSSize(width: 660, height: 780))
        w.minSize = NSSize(width: 500, height: 400)
        w.isReleasedWhenClosed = false
        w.center()
        w.level = .normal

        self.window = w

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
