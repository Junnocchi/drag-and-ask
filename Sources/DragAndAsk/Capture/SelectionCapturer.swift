import AppKit

enum SelectionCapturer {
    /// Captures the currently selected text in the frontmost app by synthesizing
    /// a ⌘C and reading the resulting pasteboard write. Returns nil if no copy
    /// was triggered (i.e. no selection or our synth events were rejected).
    static func capture() async -> String? {
        let pb = NSPasteboard.general
        let backupString = pb.string(forType: .string)
        let changeBefore = pb.changeCount

        // Let the user's real ⌘ release settle before injecting new events.
        try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms

        // Method 1: CGEvent at session-tap level (works in most apps).
        postCmdCViaCGEvent()
        if await waitForChange(pb: pb, before: changeBefore, totalMs: 250) {
            return finalize(pb: pb, backup: backupString)
        }

        // Method 2: AppleScript through System Events (more permissive route).
        postCmdCViaAppleScript()
        if await waitForChange(pb: pb, before: changeBefore, totalMs: 500) {
            return finalize(pb: pb, backup: backupString)
        }

        return nil
    }

    private static func waitForChange(pb: NSPasteboard, before: Int, totalMs: Int) async -> Bool {
        let steps = totalMs / 20
        for _ in 0..<max(steps, 1) {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before { return true }
        }
        return false
    }

    private static func finalize(pb: NSPasteboard, backup: String?) -> String? {
        let copied = pb.string(forType: .string)
        pb.clearContents()
        if let backup { pb.setString(backup, forType: .string) }
        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    private static func postCmdCViaCGEvent() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 0x08      // 'c'
        let cmdKey: CGKeyCode = 0x37    // left command

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        cDown?.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        cUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false)
        cmdUp?.flags = []

        // Session tap is less restricted than the HID tap on modern macOS.
        let tap: CGEventTapLocation = .cgSessionEventTap
        cmdDown?.post(tap: tap)
        cDown?.post(tap: tap)
        cUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
    }

    private static func postCmdCViaAppleScript() {
        let source = """
        tell application "System Events" to keystroke "c" using {command down}
        """
        guard let script = NSAppleScript(source: source) else { return }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
    }
}
