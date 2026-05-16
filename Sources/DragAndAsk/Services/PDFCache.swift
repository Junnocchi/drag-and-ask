import Foundation

actor PDFCache {
    static let shared = PDFCache()

    struct Entry {
        let mtime: Date
        var fileUri: String?     // Gemini File API URI
        var base64: String?      // inline encoding (for small files)
    }

    private var entries: [String: Entry] = [:]

    func entry(forPath path: String) -> Entry? {
        guard let current = try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date,
              let cached = entries[path],
              cached.mtime == current
        else { return nil }
        return cached
    }

    func update(path: String, fileUri: String? = nil, base64: String? = nil) {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
        var existing = entries[path] ?? Entry(mtime: mtime, fileUri: nil, base64: nil)
        existing = Entry(
            mtime: mtime,
            fileUri: fileUri ?? existing.fileUri,
            base64: base64 ?? existing.base64
        )
        entries[path] = existing
    }
}
