import Foundation

enum GeminiClient {
    static let provider: AIProvider = .gemini
    static let callTimeout: TimeInterval = 240

    static func explainSelection(_ selection: String, pdfURL: URL?) async throws -> String {
        let history = await CLISessionStore.shared.session(provider: provider, pdfURL: pdfURL)
        let isFirstCall = history == nil

        let prompt: String
        if isFirstCall {
            if let pdfURL {
                let pdfText = PDFTextExtractor.extract(from: pdfURL) ?? "(PDF 텍스트 추출 실패 — 일반 지식으로 답변하지 마시고 알 수 없다고 말씀하세요)"
                prompt = """
                \(AISystemRules.full)

                === 논문 본문 시작 (\(pdfURL.lastPathComponent)) ===
                \(pdfText)
                === 논문 본문 끝 ===

                사용자가 위 논문에서 드래그로 선택한 부분:
                \"\"\"
                \(selection)
                \"\"\"

                위 논문 본문의 실제 맥락(주변 문장, 정의, 알고리즘 등)을 근거로
                이 부분이 **무엇을 말하는 것인지** 한국어 한 문장으로 해설해주세요.
                일반 지식 추측 금지. 단순 번역 금지.
                """
            } else {
                prompt = """
                \(AISystemRules.full)

                선택한 부분:
                \"\"\"
                \(selection)
                \"\"\"

                이 부분이 **무엇을 말하는 것인지** 한국어 한 문장으로 해설해주세요. 단순 번역 금지.
                """
            }
        } else {
            prompt = """
            같은 논문에서 또 다른 부분을 선택했습니다:
            \"\"\"
            \(selection)
            \"\"\"

            이 부분이 논문 맥락에서 **무엇을 말하는 것인지** 한국어 한 문장으로 해설해주세요. 단순 번역 금지.
            """
        }
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
        let response = try await invoke(prompt: question, pdfURL: pdfURL)
        await ConversationStore.shared.append(
            .init(role: .user, promptText: question, displayText: question, userKind: .question, pdfFileUri: nil),
            provider: provider, pdfURL: pdfURL
        )
        await ConversationStore.shared.append(
            .init(role: .model, promptText: response, displayText: response, userKind: nil, pdfFileUri: nil),
            provider: provider, pdfURL: pdfURL
        )
        return response
    }

    static func connectionTest() async throws -> String {
        await CLISessionStore.shared.clearSession(provider: provider, pdfURL: nil)
        let result = try await invoke(prompt: "Reply with exactly: 연결 성공", pdfURL: nil)
        await CLISessionStore.shared.clearSession(provider: provider, pdfURL: nil)
        return result
    }

    private static func invoke(prompt: String, pdfURL: URL?) async throws -> String {
        guard let binary = ProcessRunner.findBinary(candidates: provider.binaryCandidates) else {
            throw AIError.cliNotFound(provider)
        }

        let existing = await CLISessionStore.shared.session(provider: provider, pdfURL: pdfURL)
        let sessionId = existing ?? UUID().uuidString.lowercased()
        let useResume = existing != nil

        var args: [String] = [
            "--skip-trust",
            "--approval-mode", "plan",
            "-m", AIService.currentModel,
            "-p", prompt
        ]
        args += useResume ? ["--resume", sessionId] : ["--session-id", sessionId]

        let (stdout, stderr, status) = try await ProcessRunner.run(binary: binary, arguments: args, timeout: callTimeout)
        if status != 0 { throw AIError.cliFailed(provider, status, stderr) }

        if !useResume {
            await CLISessionStore.shared.setSession(sessionId, provider: provider, pdfURL: pdfURL)
        }

        let cleaned = stripNoise(stdout)
        let extracted = ResponseSanitizer.extractFromToolCall(cleaned)
        let final = ResponseSanitizer.stripLeadingPrefixes(extracted)
        if final.isEmpty { throw AIError.empty(provider) }
        return final
    }

    private static func stripNoise(_ raw: String) -> String {
        let noisePrefixes: [String] = [
            "Ripgrep is not available",
            "Falling back to GrepTool",
            "Warning:",
            "[Routing]",
            "[LocalAgentExecutor]",
            "Error executing tool ",
            "Data collection notice",
            "DeprecationWarning",
            "update_topic(",
            "read_file(",
            "write_file(",
            "list_directory(",
            "grep_search(",
            "shell_command("
        ]
        let kept = raw.components(separatedBy: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return true }
            for p in noisePrefixes { if t.hasPrefix(p) { return false } }
            return true
        }.joined(separator: "\n")
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
