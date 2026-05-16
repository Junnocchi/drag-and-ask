import Foundation

enum ResponseSanitizer {
    /// Strip habit-of-the-model prefixes like "핵심 의미: " (optionally markdown-bold).
    static func stripLeadingPrefixes(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns: [String] = [
            "**핵심 의미**:", "**핵심의미**:", "**핵심 의미:**", "**핵심의미:**",
            "핵심 의미:", "핵심의미:",
            "**요약**:", "**요약:**", "요약:",
            "**답변**:", "**답변:**", "답변:",
            "**한 문장 요약**:", "한 문장 요약:"
        ]
        var changed = true
        while changed {
            changed = false
            for p in patterns {
                if s.lowercased().hasPrefix(p.lowercased()) {
                    s.removeFirst(p.count)
                    s = s.trimmingCharacters(in: .whitespaces)
                    changed = true
                    break
                }
            }
        }
        return s
    }

    /// Some models wrap their answer in a leaked tool call like
    /// `update_topic(strategic_intent='실제 답변')`. Extract the inner string.
    static func extractFromToolCall(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Za-z_][A-Za-z0-9_]*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*=\s*'([\s\S]*?)'\s*\)"#
        if let r = trimmed.range(of: pattern, options: .regularExpression) {
            if let re = try? NSRegularExpression(pattern: pattern),
               let m = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               m.numberOfRanges >= 2,
               let g1 = Range(m.range(at: 1), in: trimmed) {
                let inner = String(trimmed[g1])
                let tail = String(trimmed[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return tail.isEmpty ? inner : inner + "\n\n" + tail
            }
        }
        return trimmed
    }
}
