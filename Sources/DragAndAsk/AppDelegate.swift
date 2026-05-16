import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popupController: PopupController!
    private var hotkeyManager: HotkeyManager!
    private var settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popupController = PopupController()
        hotkeyManager = HotkeyManager { [weak self] in
            self?.triggerCapture()
        }

        setupStatusItem()
        hotkeyManager.start()

        if !PermissionsHelper.hasAccessibility {
            PermissionsHelper.promptAccessibility()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: "drag & ask")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open (⌘⌘)", action: #selector(triggerCapture), keyEquivalent: "")
        menu.addItem(withTitle: "Test popup with dummy data", action: #selector(showDummy), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "모든 대화 기록 초기화", action: #selector(resetAllConversations), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit drag & ask", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func triggerCapture() {
        Task { @MainActor in
            await runCapturePipeline()
        }
    }

    @objc func showDummy() {
        popupController.show(
            selection: "We propose a novel attention mechanism that scales linearly with sequence length while maintaining quadratic expressivity through low-rank approximations.",
            sourceFile: "sample.pdf",
            pdfURL: nil
        )
    }

    @objc func openSettings() {
        settingsWindowController.show()
    }

    @objc func resetAllConversations() {
        Task {
            await ConversationStore.shared.resetAll()
            await CLISessionStore.shared.clearAll()
        }
    }
    // Note: both stores already have a resetAll() that wipes across all providers.

    @MainActor
    private func runCapturePipeline() async {
        let selection = await SelectionCapturer.capture()
        let pdfPath = PreviewIntegration.frontPDFPath()

        guard let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            popupController.show(
                selection: "",
                sourceFile: "",
                pdfURL: nil,
                errorMessage: "선택된 텍스트가 없습니다. Preview에서 먼저 드래그로 선택하세요."
            )
            return
        }

        let pdfURL = pdfPath.map { URL(fileURLWithPath: $0) }
        let sourceName = pdfURL?.lastPathComponent ?? "(Preview에 PDF가 열려있지 않음)"

        popupController.show(
            selection: selection,
            sourceFile: sourceName,
            pdfURL: pdfURL
        )
    }
}
