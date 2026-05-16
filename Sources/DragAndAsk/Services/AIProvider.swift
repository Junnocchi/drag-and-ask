import Foundation

struct ModelPreset: Hashable {
    let label: String
    let value: String
}

enum AIProvider: String, CaseIterable, Codable {
    case gemini
    case claude
    case codex

    var displayName: String {
        switch self {
        case .gemini: "Gemini CLI"
        case .claude: "Claude Code"
        case .codex:  "Codex CLI"
        }
    }

    var binaryCandidates: [String] {
        switch self {
        case .gemini:
            return [
                "/opt/homebrew/bin/gemini",
                "/usr/local/bin/gemini",
                NSHomeDirectory() + "/.npm-global/bin/gemini"
            ]
        case .claude:
            return [
                NSHomeDirectory() + "/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                NSHomeDirectory() + "/.npm-global/bin/claude"
            ]
        case .codex:
            return [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                NSHomeDirectory() + "/.npm-global/bin/codex"
            ]
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: "gemini-2.5-pro"
        case .claude: "sonnet"
        case .codex:  "gpt-5"
        }
    }

    var modelPresets: [ModelPreset] {
        switch self {
        case .gemini:
            return [
                .init(label: "gemini-2.5-pro (안정, 추천)",        value: "gemini-2.5-pro"),
                .init(label: "gemini-3-pro-preview (최신, 프리뷰)", value: "gemini-3-pro-preview"),
                .init(label: "gemini-2.5-flash (빠름)",            value: "gemini-2.5-flash"),
                .init(label: "gemini-2.5-flash-lite (제일 빠름)",   value: "gemini-2.5-flash-lite"),
                .init(label: "gemini-2.0-flash",                   value: "gemini-2.0-flash")
            ]
        case .claude:
            return [
                .init(label: "opus  — 최신 Opus 자동 추종 (현재 4.7)",    value: "opus"),
                .init(label: "sonnet — 최신 Sonnet 자동 추종 (현재 4.6)", value: "sonnet"),
                .init(label: "haiku — 최신 Haiku 자동 추종 (현재 4.5)",   value: "haiku"),
                .init(label: "claude-opus-4-7 (정확한 버전)",             value: "claude-opus-4-7"),
                .init(label: "claude-sonnet-4-6 (정확한 버전)",           value: "claude-sonnet-4-6"),
                .init(label: "claude-haiku-4-5-20251001 (정확한 버전)",   value: "claude-haiku-4-5-20251001")
            ]
        case .codex:
            return [
                .init(label: "gpt-5 (최신)",        value: "gpt-5"),
                .init(label: "gpt-5-mini (가벼움)", value: "gpt-5-mini"),
                .init(label: "o3 (reasoning)",      value: "o3")
            ]
        }
    }

    var modelDefaultsKey: String {
        // Legacy key kept for Gemini to preserve existing user setting
        self == .gemini ? "GeminiModel" : "Model_\(rawValue)"
    }

    var authHint: String {
        switch self {
        case .gemini:
            return "터미널에서 `gemini` 한 번 실행 → Google 계정 OAuth"
        case .claude:
            return "터미널에서 `claude` 한 번 실행 → Claude.ai 계정 로그인"
        case .codex:
            return "터미널에서 `codex login` → ChatGPT 계정 OAuth"
        }
    }

    /// Three-step setup recipe shown verbatim in the Settings UI.
    var setupSteps: [String] {
        switch self {
        case .gemini:
            return [
                "npm install -g @google/gemini-cli",
                "gemini   # 브라우저가 열리며 Google 계정으로 OAuth",
                "gemini --skip-trust --approval-mode plan -p 'ping'   # 동작 확인"
            ]
        case .claude:
            return [
                "npm install -g @anthropic-ai/claude-code   # 또는 https://claude.ai/install.sh",
                "claude   # 브라우저가 열리며 Claude.ai 계정으로 로그인",
                "claude -p 'ping'   # 동작 확인"
            ]
        case .codex:
            return [
                "brew install codex   # 또는 npm install -g @openai/codex",
                "codex login   # 브라우저가 열리며 ChatGPT 계정으로 OAuth",
                "codex exec --skip-git-repo-check --ephemeral 'ping'   # 동작 확인"
            ]
        }
    }
}
