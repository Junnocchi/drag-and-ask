import Foundation

/// Per-PDF conversation history. Each PDF (keyed by absolute path) gets its own
/// multi-turn conversation. Turns store both the raw API prompt and a separate
/// display text — useful when the prompt wraps a selection in scaffolding text
/// we don't want to show to the user.
actor ConversationStore {
    static let shared = ConversationStore()

    struct Turn: Identifiable, Sendable {
        enum Role: String, Sendable { case user, model }
        enum UserKind: Sendable { case selection, question }

        let id = UUID()
        let role: Role
        /// Text actually sent to the model.
        let promptText: String
        /// Text shown in the chat UI (may equal promptText for model turns and typed questions).
        let displayText: String
        /// Set only on user turns; nil for model turns.
        let userKind: UserKind?
        /// Set only on the first user turn of a conversation.
        let pdfFileUri: String?
    }

    private var conversations: [String: [Turn]] = [:]

    private func key(forPDF pdfURL: URL?) -> String {
        pdfURL?.path ?? "_no_pdf"
    }

    func turns(forPDF pdfURL: URL?) -> [Turn] {
        conversations[key(forPDF: pdfURL)] ?? []
    }

    func append(_ turn: Turn, forPDF pdfURL: URL?) {
        conversations[key(forPDF: pdfURL), default: []].append(turn)
    }

    func reset(forPDF pdfURL: URL?) {
        conversations[key(forPDF: pdfURL)] = nil
    }

    func resetAll() {
        conversations.removeAll()
    }

    func userTurnCount(forPDF pdfURL: URL?) -> Int {
        let turns = conversations[key(forPDF: pdfURL)] ?? []
        return turns.filter { $0.role == .user }.count
    }
}
