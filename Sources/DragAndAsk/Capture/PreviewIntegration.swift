import AppKit

enum PreviewIntegration {
    /// Returns POSIX path of the frontmost Preview document, or nil if Preview isn't running,
    /// has no open document, or we don't have Apple Events permission.
    static func frontPDFPath() -> String? {
        let source = """
        tell application "System Events"
            if not (exists process "Preview") then return ""
        end tell
        tell application "Preview"
            try
                if (count of documents) is 0 then return ""
                set p to path of front document
                return p
            on error
                return ""
            end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        guard let path = result.stringValue, !path.isEmpty else { return nil }
        return path
    }
}
