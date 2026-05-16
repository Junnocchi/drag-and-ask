import Foundation

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum GeminiError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case decoding(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API 키가 설정되지 않았습니다. 메뉴바 > Settings에서 입력하세요."
        case .http(let code, let body):
            return "Gemini API 오류 (\(code)): \(body.prefix(200))"
        case .decoding(let detail):
            return "응답 파싱 실패: \(detail)"
        case .empty:
            return "Gemini에서 빈 응답을 받았습니다."
        }
    }
}

struct GeminiService {
    static let defaultModel = "gemini-2.5-flash"
    static let modelDefaultsKey = "GeminiModel"

    static var model: String {
        UserDefaults.standard.string(forKey: modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? defaultModel
    }

    static let systemInstruction = """
    당신은 학술 논문 독해를 돕는 한국어 어시스턴트입니다.
    사용자가 첫 메시지에 첨부한 PDF는 그들이 지금 읽고 있는 논문이며,
    이후 같은 대화의 모든 질문은 그 논문에 대한 것입니다.

    **길이 규칙 (가장 중요):**
    - 기본: 딱 한 문장으로 핵심 의미만 답하세요. 답변은 바로 그 한 문장 본문으로 시작해야 합니다.
    - "핵심 의미:", "요약:", "답변:" 같은 머리말(prefix)을 절대 붙이지 마세요. 본문만 출력하세요.
    - 절대 그 한 문장을 넘어가지 마세요. 배경 설명/예시/추가 맥락 금지.
    - 예외: 사용자 메시지에 "자세하게" 라는 단어가 포함되어 있을 때만, 헤더·불릿·수식 풀이 등을 사용해 충분히 풀어서 설명하세요.

    공통 규칙:
    - 항상 한국어로 답하세요.
    - 어려운 용어가 있어도 한 문장 규칙을 어기지 말 것 (자세하게 모드에서만 풀어 설명).
    - PDF에서 잘못 추출된 줄바꿈/하이픈은 알아서 보정해 해석하세요.
    - 이전 질문을 기억해서 같은 설명을 반복하지 마세요.
    """

    // MARK: - Public entry points

    /// Selection captured from ⌘⌘. Wraps it as the prompt to the model and
    /// stores the raw selection as the display text.
    static func explainSelection(_ selection: String, pdfURL: URL?) async throws -> String {
        let history = await ConversationStore.shared.turns(forPDF: pdfURL)
        let prompt = history.isEmpty
            ? "아래는 위 논문에서 선택한 부분입니다. 핵심 의미만 한 문장으로 답해주세요.\n\n\"\"\"\n\(selection)\n\"\"\""
            : "같은 논문에서 또 선택한 부분입니다. 핵심 의미만 한 문장으로 답해주세요.\n\n\"\"\"\n\(selection)\n\"\"\""
        return try await send(
            prompt: prompt,
            display: selection,
            userKind: .selection,
            pdfURL: pdfURL
        )
    }

    /// Typed follow-up question from the popup input.
    static func askFollowUp(_ question: String, pdfURL: URL?) async throws -> String {
        return try await send(
            prompt: question,
            display: question,
            userKind: .question,
            pdfURL: pdfURL
        )
    }

    /// One-shot test that does NOT touch any conversation history. Used by Settings.
    static func connectionTest() async throws -> String {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": "Reply in Korean only."]]],
            "contents": [[
                "role": "user",
                "parts": [["text": "Reply with exactly: 연결 성공"]]
            ]],
            "generationConfig": ["temperature": 0]
        ]
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: req)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw GeminiError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try parseResponse(data)
    }

    // MARK: - Internal sender

    private static func send(
        prompt: String,
        display: String,
        userKind: ConversationStore.Turn.UserKind,
        pdfURL: URL?
    ) async throws -> String {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }

        var pdfFileUri: String? = nil
        if let pdfURL {
            pdfFileUri = try await ensurePDFUploaded(pdfURL, apiKey: apiKey)
        }

        let history = await ConversationStore.shared.turns(forPDF: pdfURL)
        var contents: [[String: Any]] = []
        for turn in history {
            contents.append(turnToJSON(turn))
        }

        let attachPDF = history.isEmpty
        let newTurn = ConversationStore.Turn(
            role: .user,
            promptText: prompt,
            displayText: display,
            userKind: userKind,
            pdfFileUri: attachPDF ? pdfFileUri : nil
        )
        contents.append(turnToJSON(newTurn))

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": contents,
            "generationConfig": ["temperature": 0.3]
        ]

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: req)
        if let code = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw GeminiError.http(code, String(data: data, encoding: .utf8) ?? "")
        }

        let text = try parseResponse(data)

        await ConversationStore.shared.append(newTurn, forPDF: pdfURL)
        await ConversationStore.shared.append(
            ConversationStore.Turn(
                role: .model,
                promptText: text,
                displayText: text,
                userKind: nil,
                pdfFileUri: nil
            ),
            forPDF: pdfURL
        )

        return text
    }

    // MARK: - Helpers

    private static func turnToJSON(_ turn: ConversationStore.Turn) -> [String: Any] {
        var parts: [[String: Any]] = []
        if let uri = turn.pdfFileUri {
            parts.append([
                "fileData": [
                    "mimeType": "application/pdf",
                    "fileUri": uri
                ]
            ])
        }
        parts.append(["text": turn.promptText])
        return ["role": turn.role.rawValue, "parts": parts]
    }

    private static func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decoding("top-level JSON")
        }
        guard let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty,
              let content = candidates[0]["content"] as? [String: Any],
              let respParts = content["parts"] as? [[String: Any]]
        else {
            throw GeminiError.decoding("candidates/content/parts")
        }
        let text = respParts.compactMap { $0["text"] as? String }.joined()
        if text.isEmpty { throw GeminiError.empty }
        return stripLeadingPrefixes(text)
    }

    /// Strip habit-of-the-model prefixes like "핵심 의미: ", "요약: ", "답변: "
    /// (optionally markdown-bold) at the very start of the response.
    private static func stripLeadingPrefixes(_ text: String) -> String {
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

    private static func ensurePDFUploaded(_ pdfURL: URL, apiKey: String) async throws -> String {
        let path = pdfURL.path
        if let cached = await PDFCache.shared.entry(forPath: path), let uri = cached.fileUri {
            return uri
        }
        let uri = try await uploadFileAPI(url: pdfURL, apiKey: apiKey)
        await PDFCache.shared.update(path: path, fileUri: uri)
        return uri
    }

    private static func uploadFileAPI(url: URL, apiKey: String) async throws -> String {
        let data = try Data(contentsOf: url)
        let mime = "application/pdf"

        var startReq = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files?key=\(apiKey)")!)
        startReq.httpMethod = "POST"
        startReq.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startReq.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startReq.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startReq.setValue(mime, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let meta: [String: Any] = ["file": ["display_name": url.lastPathComponent]]
        startReq.httpBody = try JSONSerialization.data(withJSONObject: meta)

        let (_, startResp) = try await URLSession.shared.data(for: startReq)
        guard let http = startResp as? HTTPURLResponse,
              let uploadURL = http.value(forHTTPHeaderField: "X-Goog-Upload-URL") ?? http.value(forHTTPHeaderField: "x-goog-upload-url")
        else {
            throw GeminiError.http((startResp as? HTTPURLResponse)?.statusCode ?? -1, "no upload URL")
        }

        var uploadReq = URLRequest(url: URL(string: uploadURL)!)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        uploadReq.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadReq.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadReq.httpBody = data

        let (respData, uploadResp) = try await URLSession.shared.data(for: uploadReq)
        if let code = (uploadResp as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
            throw GeminiError.http(code, String(data: respData, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let file = json["file"] as? [String: Any],
              let uri = file["uri"] as? String
        else {
            throw GeminiError.decoding("file upload response")
        }
        return uri
    }
}
