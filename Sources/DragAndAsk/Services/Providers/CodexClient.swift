import Foundation

/// Codex CLI doesn't have a clean session-resume CLI surface like the others,
/// so we treat every call as stateless and feed the full transcript (PDF text
/// once on the first call, since Codex sessions persist via our own state) as
/// part of the prompt. This is slower per call but uniform and reliable.
enum CodexClient {
    static let provider: AIProvider = .codex
    static let callTimeout: TimeInterval = 300

    static func explainSelection(_ selection: String, pdfURL: URL?) async throws -> String {
        let history = await ConversationStore.shared.turns(provider: provider, pdfURL: pdfURL)
        let prompt = buildPrompt(newUserText: """
        사용자가 드래그로 선택한 부분:
        \"\"\"
        \(selection)
        \"\"\"

        이 부분이 무엇을 말하는 것인지 한국어 한 문장으로 해설해주세요. 단순 번역 금지.
        """, history: history, pdfURL: pdfURL, isFirstTurn: history.isEmpty)

        let response = try await invoke(prompt: prompt, pdfURL: pdfURL)
        await ConversationStore.shared.append(
            .init(role: .user, promptText: prompt, displayText: selection, userKind: .selection, pdfFileUri: nil),
            provider: provider, pdfURL: pdfURL
        )
        await ConversationStore.shared.append(
            .init(role: .model, promptText: response, displayText: response, userKind: nil, pdfFileUri: nil),
            provider: provider, pdfURL: pdfURL
        )
        return response
    }

    static func askFollowUp(_ question: String, pdfURL: URL?) async throws -> String {
        let history = await ConversationStore.shared.turns(provider: provider, pdfURL: pdfURL)
        let prompt = buildPrompt(newUserText: question, history: history, pdfURL: pdfURL, isFirstTurn: history.isEmpty)

        let response = try await invoke(prompt: prompt, pdfURL: pdfURL)
        await ConversationStore.shared.append(
            .init(role: .user, promptText: prompt, displayText: question, userKind: .question, pdfFileUri: nil),
            provider: provider, pdfURL: pdfURL
        )
        await ConversationStore.shared.append(
            .init(role: .model, promptText: response, displayText: response, userKind: nil, pdfFileUri: nil),
            provider: provider, pdfURL: pdfURL
        )
        return response
    }

    static func connectionTest() async throws -> String {
        let prompt = AISystemRules.full + "\n\nReply with exactly: 연결 성공"
        return try await invoke(prompt: prompt, pdfURL: nil)
    }

    private static func buildPrompt(newUserText: String, history: [ConversationStore.Turn], pdfURL: URL?, isFirstTurn: Bool) -> String {
        var parts: [String] = [AISystemRules.full]
        if let pdfURL {
            let pdfText = PDFTextExtractor.extract(from: pdfURL) ?? "(PDF 텍스트 추출 실패)"
            parts.append("=== 논문 본문 시작 (\(pdfURL.lastPathComponent)) ===\n\(pdfText)\n=== 논문 본문 끝 ===")
        }
        if !history.isEmpty {
            parts.append("=== 이전 대화 ===")
            for turn in history {
                let role = turn.role == .user ? "사용자" : "어시스턴트"
                parts.append("\(role): \(turn.displayText)")
            }
            parts.append("=== 이전 대화 끝 ===")
        }
        parts.append("이번 질문:\n\(newUserText)")
        return parts.joined(separator: "\n\n")
    }

    private static func invoke(prompt: String, pdfURL: URL?) async throws -> String {
        guard let binary = ProcessRunner.findBinary(candidates: provider.binaryCandidates) else {
            throw AIError.cliNotFound(provider)
        }

        // Write the final-message output to a temp file for clean parsing.
        let tempOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("drag-and-ask-codex-\(UUID().uuidString).txt")

        let args: [String] = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "-s", "read-only",
            "-m", AIService.currentModel,
            "-o", tempOut.path,
            prompt
        ]

        let (_, stderr, status) = try await ProcessRunner.run(binary: binary, arguments: args, timeout: callTimeout)
        if status != 0 {
            try? FileManager.default.removeItem(at: tempOut)
            throw AIError.cliFailed(provider, status, stderr)
        }

        let raw: String
        if FileManager.default.fileExists(atPath: tempOut.path),
           let data = try? Data(contentsOf: tempOut),
           let text = String(data: data, encoding: .utf8) {
            raw = text
        } else {
            // Output file missing → fall back to stderr/empty.
            raw = ""
        }
        try? FileManager.default.removeItem(at: tempOut)

        let final = ResponseSanitizer.stripLeadingPrefixes(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if final.isEmpty { throw AIError.empty(provider) }
        return final
    }
}
