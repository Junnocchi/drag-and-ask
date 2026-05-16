# drag & ask

영어 논문을 macOS Preview에서 읽다가 어려운 부분을 만나면 **드래그 + ⌘⌘** 한 번으로 Gemini · Claude · Codex CLI 중 하나가 그 자리에서 한국어로 해설해주는 메뉴바 앱.

- PDF 전체가 컨텍스트로 들어가 "위 논문의 4장에서 정의한 X는…" 같이 맥락 인지 답변
- 같은 논문 안에서 ⌘⌘은 같은 대화로 누적 → 이전 Q&A 기억
- 기본은 한 문장만, "자세하게" 라고 적으면 풀어서 설명
- 응답은 마크다운 + GFM 테이블 + **LaTeX 수식** 모두 렌더링되는 chat UI에 누적
- 세션 quota 사용률(Codex 5h/주간, Claude 5h/7d)을 헤더에 표시

## 사용 흐름

1. macOS Preview에서 PDF 열기
2. 본문에서 이해 안 가는 부분을 드래그로 선택
3. `⌘` 키를 두 번 빠르게 누름
4. 팝업에 한국어 해설. 후속 질문은 그 자리에서 타이핑
5. 같은 논문 안에서 또 ⌘⌘ → 모델이 이전 대화 기억한 채 답변

## 요구 사항

- macOS 14 (Sonoma) 이상, **Apple Silicon** (M1/M2/M3/M4)
- Xcode Command Line Tools 16+ (Swift 6 빌드)
- AI provider 중 **하나는** 설치/인증되어 있어야 함:
  - **Gemini CLI** — `npm install -g @google/gemini-cli` → `gemini` → Google 계정 OAuth
  - **Claude Code** — `npm install -g @anthropic-ai/claude-code` → `claude` → Claude.ai 로그인
  - **Codex CLI** — `brew install codex` 또는 `npm install -g @openai/codex` → `codex login`

> 별도 API 키는 필요 없습니다. 각 CLI는 사용자 구독 인증을 직접 사용합니다.

## 빌드 & 실행

```bash
./build.sh
open build/DragAndAsk.app
```

배포용 zip (다른 Mac으로 옮길 때):

```bash
./dist.sh
# → dist/DragAndAsk-v0.2.0-<arch>.zip
```

## 첫 실행 시 권한

전부 첫 ⌘⌘ 시도 시 macOS가 묻습니다.

1. **손쉬운 사용 (Accessibility)** — 전역 키 감지 + 합성 ⌘C에 필요. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 `drag & ask` 토글 ON 후 앱 재시작.
2. **자동화 (Apple Events)** — Preview의 현재 PDF 경로를 가져오기 위해 AppleScript 호출. 다이얼로그에서 "허용".
3. 메뉴바 📖 → **Settings** → provider/모델 선택 → 연결 테스트

## 메뉴바 메뉴

- **Open (⌘⌘)** — 즉시 캡처 파이프라인 (디버그용)
- **Test popup with dummy data** — 모델 호출 없이 UI 미리보기
- **모든 대화 기록 초기화** — 메모리에 있는 모든 (provider, PDF) 대화 삭제
- **Settings…** — provider/모델 관리, 인증 가이드
- **Quit drag & ask**

## 팝업 UI

- 헤더 1줄: 파일명, 새 대화 버튼, ESC 안내
- 헤더 2줄: 현재 provider · 모델 · 질문 수
- 헤더 3줄 (quota): 사용 중인 provider의 세션 사용률
  - Codex: `(5h) 23% reset 14:30 · (wk) 41% reset 5/20 09:00`
  - Claude: `(5h) 18% reset 17:42 · (7d) 9% reset 5/22 09:00`
  - Gemini: "헤드리스 quota 노출 없음" (CLI가 정보를 안 줌)
- 채팅 영역: 선택/질문(파란 버블) ↔ 모델 응답(회색, 마크다운+수식 풀 렌더링)
- 후속 질문 입력 (Enter로 전송)

창은 자유 리사이즈 + 전체화면 가능. 가로를 줄이면 응답 버블 컨텐츠가 reflow됨.

## 디렉토리 구조

```
.
├── Package.swift                       SwiftPM 매니페스트
├── build.sh                            빌드 + .app 번들 래핑
├── dist.sh                             배포용 zip 생성
├── bundle/
│   ├── Info.plist
│   ├── DragAndAsk.entitlements         automation, network
│   └── icon.png                        1024×1024 앱 아이콘 소스
├── Tools/
│   └── generate_icon.swift             기본 아이콘 PNG 생성기
└── Sources/DragAndAsk/
    ├── DragAndAskApp.swift             @main SwiftUI App
    ├── AppDelegate.swift               상태바, 핫키, 파이프라인
    ├── Hotkey/HotkeyManager.swift      ⌘ 더블탭 감지
    ├── Capture/
    │   ├── SelectionCapturer.swift     합성 ⌘C → NSPasteboard
    │   └── PreviewIntegration.swift    AppleScript로 Preview 문서 경로
    ├── Services/
    │   ├── AIService.swift             provider 디스패처
    │   ├── AIProvider.swift            provider enum + 메타데이터
    │   ├── AIError.swift               에러 타입
    │   ├── AISystemRules.swift         공용 시스템 프롬프트
    │   ├── ProcessRunner.swift         subprocess 공용 헬퍼
    │   ├── ResponseSanitizer.swift     응답 후처리 (prefix/툴콜 제거)
    │   ├── PDFTextExtractor.swift      PDFKit 텍스트 추출
    │   ├── ConversationStore.swift     (provider, PDF)별 대화 히스토리
    │   ├── CLISessionStore.swift       (provider, PDF)별 세션 UUID
    │   ├── Quota.swift                 quota 데이터 모델 + 표시 포맷
    │   └── Providers/
    │       ├── GeminiClient.swift      gemini CLI 호출
    │       ├── ClaudeClient.swift      claude CLI 호출
    │       ├── CodexClient.swift       codex CLI 호출
    │       ├── CodexQuotaProbe.swift   codex app-server JSON-RPC
    │       └── ClaudeQuotaProbe.swift  statusLine sidechannel
    ├── Popup/
    │   ├── PopupController.swift       NSPanel
    │   ├── PopupView.swift             Chat UI
    │   ├── PopupViewModel.swift        상태
    │   └── RichResponseView.swift      WKWebView + marked + KaTeX
    ├── Settings/
    │   ├── SettingsView.swift          provider/모델/인증 가이드
    │   └── SettingsWindowController.swift
    └── Util/
        └── PermissionsHelper.swift     손쉬운 사용 권한 안내
```

## 알려진 한계

- **드래그 선택이 없으면**: "선택된 텍스트가 없습니다" 표시. 클립보드 fallback은 의도적으로 안 함.
- **Preview 외 앱**: PDF 컨텍스트 없이 선택 텍스트만 전달.
- **Claude quota probe**: PTY 띄우고 statusLine 캡처라 약 20초 소요. 자주 새로고침 권장 X.
- **Codex weekly limit**: 무료/Plus 사용자는 7일 한도가 있음. probe 결과로 확인 가능.
- **대화 기록**: 앱 재시작 시 메모리에서 비워짐.
- **sandbox off**: 외부 파일 읽기, subprocess 호출, AppleScript 때문에 비활성.

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| 빌드 실패 `failed to build module 'Swift'` | CLT 버전 오래됨. `sudo softwareupdate --install "Command Line Tools for Xcode 26.5-26.5"` |
| ⌘⌘ 눌러도 팝업 안 뜸 | 손쉬운 사용 권한 없음. 시스템 설정 → 손쉬운 사용에서 추가 후 앱 재실행 |
| "선택된 텍스트가 없습니다" | Preview에서 드래그 선택 후 ⌘⌘. 합성 ⌘C 실패 시 손쉬운 사용 권한 확인 |
| `gemini/claude/codex CLI를 찾을 수 없습니다` | 해당 CLI 미설치. Settings에 있는 설치 명령어로 설치 |
| CLI 호출 오류 (401/403) | 해당 CLI 인증 만료. 터미널에서 `gemini` / `claude` / `codex login` 다시 실행 |
| Codex 호출이 "usage limit" | 주간 한도 초과. probe로 reset 시각 확인 |

## 라이선스

MIT. `LICENSE` 참고.

## 기여

이슈/PR 환영. 큰 변경은 먼저 이슈로 의논해주세요.
