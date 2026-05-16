import Foundation

/// Per-(provider, PDF) conversation history kept in memory for the lifetime of
/// the app. Each combination gets its own chat-UI history so switching provider
/// or PDF doesn't mix turns from different model sessions.
actor ConversationStore {
    static let shared = ConversationStore()

    struct Turn: Identifiable, Sendable {
        enum Role: String, Sendable { case user, model }
        enum UserKind: Sendable { case selection, question }

        let id = UUID()
        let role: Role
        let promptText: String
        let displayText: String
        let userKind: UserKind?
        let pdfFileUri: String?
    }

    private var conversations: [String: [Turn]] = [:]

    private func key(provider: AIProvider, pdfURL: URL?) -> String {
        "\(provider.rawValue):\(pdfURL?.path ?? "_no_pdf")"
    }

    func turns(provider: AIProvider, pdfURL: URL?) -> [Turn] {
        conversations[key(provider: provider, pdfURL: pdfURL)] ?? []
    }

    func append(_ turn: Turn, provider: AIProvider, pdfURL: URL?) {
        conversations[key(provider: provider, pdfURL: pdfURL), default: []].append(turn)
    }

    func reset(provider: AIProvider, pdfURL: URL?) {
        conversations[key(provider: provider, pdfURL: pdfURL)] = nil
    }

    func resetAll() {
        conversations.removeAll()
    }

    func resetAllForCurrentPDF(pdfURL: URL?) {
        for p in AIProvider.allCases {
            conversations[key(provider: p, pdfURL: pdfURL)] = nil
        }
    }

    func userTurnCount(provider: AIProvider, pdfURL: URL?) -> Int {
        let turns = conversations[key(provider: provider, pdfURL: pdfURL)] ?? []
        return turns.filter { $0.role == .user }.count
    }
}
