import Foundation

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Dispatcher that routes calls to the currently-selected CLI provider.
/// (Kept under the GeminiService name for now to avoid touching every call site.)
struct AIService {
    static let providerDefaultsKey = "AIProvider"

    static var currentProvider: AIProvider {
        let raw = UserDefaults.standard.string(forKey: providerDefaultsKey) ?? AIProvider.gemini.rawValue
        return AIProvider(rawValue: raw) ?? .gemini
    }

    static var currentModel: String {
        let key = currentProvider.modelDefaultsKey
        return UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? currentProvider.defaultModel
    }

    static func explainSelection(_ selection: String, pdfURL: URL?) async throws -> String {
        switch currentProvider {
        case .gemini: try await GeminiClient.explainSelection(selection, pdfURL: pdfURL)
        case .claude: try await ClaudeClient.explainSelection(selection, pdfURL: pdfURL)
        case .codex:  try await CodexClient.explainSelection(selection, pdfURL: pdfURL)
        }
    }

    static func askFollowUp(_ question: String, pdfURL: URL?) async throws -> String {
        switch currentProvider {
        case .gemini: try await GeminiClient.askFollowUp(question, pdfURL: pdfURL)
        case .claude: try await ClaudeClient.askFollowUp(question, pdfURL: pdfURL)
        case .codex:  try await CodexClient.askFollowUp(question, pdfURL: pdfURL)
        }
    }

    static func connectionTest() async throws -> String {
        switch currentProvider {
        case .gemini: try await GeminiClient.connectionTest()
        case .claude: try await ClaudeClient.connectionTest()
        case .codex:  try await CodexClient.connectionTest()
        }
    }
}

/// Backward-compatible alias so existing callers keep working.
typealias GeminiService = AIService
