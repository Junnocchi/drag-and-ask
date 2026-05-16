import Foundation
import Combine

/// Display-only representation of a conversation turn for the chat UI.
struct DisplayTurn: Identifiable, Equatable {
    enum Kind: Equatable {
        case userSelection
        case userQuestion
        case modelReply
        case modelLoading       // placeholder shown while waiting for response
        case modelError(String) // failed turn
    }
    let id: UUID
    let kind: Kind
    let text: String
}

@MainActor
final class PopupViewModel: ObservableObject {
    @Published var sourceFile: String = ""
    @Published var pdfURL: URL?
    @Published var turns: [DisplayTurn] = []
    @Published var isLoading: Bool = false
    @Published var followUp: String = ""
    @Published var topErrorMessage: String?

    private var currentTask: Task<Void, Never>?
    private var loadingPlaceholderID: UUID?

    func reset() {
        currentTask?.cancel()
        sourceFile = ""
        pdfURL = nil
        turns = []
        followUp = ""
        isLoading = false
        topErrorMessage = nil
        loadingPlaceholderID = nil
    }

    /// Called when ⌘⌘ fires.
    func start(selection: String, sourceFile: String, pdfURL: URL?, errorMessage: String? = nil) {
        currentTask?.cancel()
        self.sourceFile = sourceFile
        self.pdfURL = pdfURL
        self.followUp = ""
        self.topErrorMessage = errorMessage

        // Load any existing history for this PDF into the chat view.
        Task { [weak self] in
            guard let self else { return }
            let existing = await ConversationStore.shared.turns(forPDF: pdfURL).map { Self.makeDisplayTurn($0) }
            await MainActor.run {
                self.turns = existing
                if errorMessage == nil && !selection.isEmpty {
                    self.sendSelection(selection)
                }
            }
        }
    }

    private func sendSelection(_ selection: String) {
        let userTurn = DisplayTurn(id: UUID(), kind: .userSelection, text: selection)
        let loadingTurn = DisplayTurn(id: UUID(), kind: .modelLoading, text: "")
        turns.append(userTurn)
        turns.append(loadingTurn)
        loadingPlaceholderID = loadingTurn.id
        runCall {
            try await GeminiService.explainSelection(selection, pdfURL: self.pdfURL)
        }
    }

    func askFollowUp() {
        let question = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        followUp = ""

        let userTurn = DisplayTurn(id: UUID(), kind: .userQuestion, text: question)
        let loadingTurn = DisplayTurn(id: UUID(), kind: .modelLoading, text: "")
        turns.append(userTurn)
        turns.append(loadingTurn)
        loadingPlaceholderID = loadingTurn.id
        runCall {
            try await GeminiService.askFollowUp(question, pdfURL: self.pdfURL)
        }
    }

    private func runCall(_ op: @escaping () async throws -> String) {
        currentTask?.cancel()
        isLoading = true
        topErrorMessage = nil
        let url = pdfURL
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await op()
                if Task.isCancelled { return }
                // Reload the canonical history from the store so optimistic
                // turns get replaced with the persisted versions (preserves IDs/order).
                let canonical = await ConversationStore.shared.turns(forPDF: url).map { Self.makeDisplayTurn($0) }
                await MainActor.run {
                    self.turns = canonical
                    self.isLoading = false
                    self.loadingPlaceholderID = nil
                    _ = text  // already in canonical
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    // Replace the loading placeholder with an error bubble.
                    if let id = self.loadingPlaceholderID,
                       let idx = self.turns.firstIndex(where: { $0.id == id }) {
                        self.turns[idx] = DisplayTurn(
                            id: id,
                            kind: .modelError(error.localizedDescription),
                            text: error.localizedDescription
                        )
                    }
                    self.loadingPlaceholderID = nil
                    self.isLoading = false
                }
            }
        }
    }

    func resetConversation() {
        let url = pdfURL
        Task { [weak self] in
            guard let self else { return }
            await ConversationStore.shared.reset(forPDF: url)
            await MainActor.run {
                self.turns = []
            }
        }
    }

    var userTurnCount: Int {
        turns.filter {
            switch $0.kind {
            case .userSelection, .userQuestion: return true
            default: return false
            }
        }.count
    }

    private static func makeDisplayTurn(_ turn: ConversationStore.Turn) -> DisplayTurn {
        let kind: DisplayTurn.Kind
        switch turn.role {
        case .user:
            kind = (turn.userKind == .selection) ? .userSelection : .userQuestion
        case .model:
            kind = .modelReply
        }
        return DisplayTurn(id: turn.id, kind: kind, text: turn.displayText)
    }
}
