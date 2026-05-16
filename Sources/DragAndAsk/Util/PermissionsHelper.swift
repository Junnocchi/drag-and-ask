import AppKit
import ApplicationServices

enum PermissionsHelper {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func promptAccessibility() -> Bool {
        let options: [String: Bool] = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
