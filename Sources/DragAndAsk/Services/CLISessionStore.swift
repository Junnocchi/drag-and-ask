import Foundation

/// Maps (provider, PDF path) → CLI session UUID so subsequent ⌘⌘ on the same
/// paper resume the same conversation in the model's session store.
actor CLISessionStore {
    static let shared = CLISessionStore()

    private var sessions: [String: String] = [:]

    private func key(provider: AIProvider, pdfURL: URL?) -> String {
        "\(provider.rawValue):\(pdfURL?.path ?? "_no_pdf")"
    }

    func session(provider: AIProvider, pdfURL: URL?) -> String? {
        sessions[key(provider: provider, pdfURL: pdfURL)]
    }

    func setSession(_ id: String, provider: AIProvider, pdfURL: URL?) {
        sessions[key(provider: provider, pdfURL: pdfURL)] = id
    }

    func clearSession(provider: AIProvider, pdfURL: URL?) {
        sessions[key(provider: provider, pdfURL: pdfURL)] = nil
    }

    func clearAllForCurrentPDF(pdfURL: URL?) {
        for p in AIProvider.allCases {
            sessions[key(provider: p, pdfURL: pdfURL)] = nil
        }
    }

    func clearAll() {
        sessions.removeAll()
    }
}
