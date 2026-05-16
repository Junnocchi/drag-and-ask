import Foundation
import PDFKit

/// Extracts plain text from a PDF using PDFKit. Modern papers usually have a
/// text layer; scanned-only PDFs would need OCR (not handled here).
enum PDFTextExtractor {
    /// Returns the full text content of the PDF, with form-feed page separators removed.
    /// Returns nil if PDFKit can't open the file or the document has no extractable text.
    static func extract(from url: URL, maxChars: Int = 400_000) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        guard let raw = doc.string, !raw.isEmpty else { return nil }

        // Normalize: trim weird control chars, collapse repeated whitespace lightly.
        var s = raw.replacingOccurrences(of: "\u{000C}", with: "\n")  // form feed -> newline
        // Cap length so we never blow past a reasonable token budget.
        if s.count > maxChars {
            let idx = s.index(s.startIndex, offsetBy: maxChars)
            s = String(s[..<idx]) + "\n…[이하 본문 생략]"
        }
        return s
    }
}
