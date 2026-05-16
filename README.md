# drag & ask

영어 논문을 macOS Preview에서 읽다가 어려운 부분을 만나면 **드래그 + ⌘⌘** 한 번으로 Gemini가 그 자리에서 한국어로 해석해주는 메뉴바 앱.

- PDF 전체가 컨텍스트로 들어가서 "위 논문의 4장에서 정의한 X는…" 같이 맥락 인지 답변
- 같은 논문 안에서 ⌘⌘은 같은 대화로 누적 → 이전 Q&A 기억
- 기본은 한 문장만, "자세하게" 라고 적으면 풀어서 설명
- 결과는 Spotlight-style 팝업의 chat UI에 쌓임

## 사용 흐름

1. macOS Preview에서 PDF 열기
2. 본문에서 이해 안 가는 부분을 드래그로 선택
3. `⌘` 키를 두 번 빠르게 누름
4. 팝업에 한국어 해석. 후속 질문은 그 자리에서 타이핑

## 요구 사항

- macOS 14 (Sonoma) 이상, **Apple Silicon** (M1/M2/M3/M4)
- Xcode Command Line Tools 16+ (Swift 6 빌드)
- Google AI Studio API 키 (무료 티어 가능) — https://aistudio.google.com/apikey

## 빌드 & 실행

```bash
./build.sh
open build/DragAndAsk.app
```

배포용 zip (다른 Mac으로 옮길 때):

```bash
./dist.sh
# → dist/DragAndAsk-v0.1.0-<arch>.zip
```

## 첫 실행 시 권한

전부 첫 ⌘⌘ 시도 시 macOS가 묻습니다.

1. **손쉬운 사용 (Accessibility)** — 전역 키 감지 + 합성 ⌘C에 필요. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 `drag & ask` 토글 ON 후 앱 재시작.
2. **자동화 (Apple Events)** — Preview의 현재 PDF 경로를 가져오기 위해 AppleScript 호출. 다이얼로그에서 "허용".
3. 메뉴바 📖 → **Settings** → Gemini API 키 입력 + 모델 선택(기본 `gemini-2.5-flash`)

## 아이콘 커스터마이즈

`bundle/icon.png` (1024×1024 PNG)를 원하는 이미지로 바꾸고 `./build.sh` 다시 실행하면 됩니다. 기본 아이콘은 `swift Tools/generate_icon.swift`로 재생성 가능.

## 디렉토리 구조

```
.
├── Package.swift                    SwiftPM 매니페스트
├── build.sh                         빌드 + .app 번들 래핑
├── dist.sh                          배포용 zip 생성
├── bundle/
│   ├── Info.plist
│   ├── DragAndAsk.entitlements      automation, network
│   └── icon.png                     1024×1024 앱 아이콘 소스
├── Tools/
│   └── generate_icon.swift          기본 아이콘 PNG 생성기
└── Sources/DragAndAsk/
    ├── DragAndAskApp.swift          @main SwiftUI App
    ├── AppDelegate.swift            상태바, 핫키, 파이프라인
    ├── Hotkey/HotkeyManager.swift   ⌘ 더블탭 감지
    ├── Capture/
    │   ├── SelectionCapturer.swift  합성 ⌘C → NSPasteboard
    │   └── PreviewIntegration.swift AppleScript로 Preview 문서 경로
    ├── Services/
    │   ├── GeminiService.swift      generateContent REST
    │   ├── ConversationStore.swift  PDF별 멀티턴 히스토리
    │   └── PDFCache.swift           File API URI 캐시
    ├── Popup/
    │   ├── PopupController.swift    NSPanel
    │   ├── PopupView.swift          Chat UI
    │   └── PopupViewModel.swift     상태
    ├── Settings/
    │   ├── SettingsView.swift       API 키 / 모델 입력
    │   ├── SettingsWindowController.swift
    │   └── KeychainHelper.swift     Keychain 저장
    └── Util/
        └── PermissionsHelper.swift
```

## 메뉴바 메뉴

- **Open (⌘⌘)** — 즉시 캡처 파이프라인 (디버그용)
- **Test popup with dummy data** — Gemini 호출 없이 UI 미리보기
- **모든 대화 기록 초기화** — 메모리에 있는 모든 PDF의 대화 삭제
- **Settings…** — API 키 / 모델 관리
- **Quit drag & ask**

## 알려진 한계

- **드래그 선택이 없으면**: "선택된 텍스트가 없습니다" 표시. 클립보드 fallback은 의도적으로 안 함 (예측 가능성).
- **Preview 외 앱**: PDF 컨텍스트 없이 선택 텍스트만으로 동작 (그래도 답변은 나옴).
- **50MB 초과 PDF**: File API로 자동 업로드, 첫 호출만 수 초.
- **대화 기록**: 앱 재시작 시 비워짐 (향후 영구 저장 가능).
- **sandbox off**: 외부 파일 읽기, Apple Events 호출 때문에 비활성. 본인 사용 전제.

## 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| 빌드 실패 `failed to build module 'Swift'` | CLT 버전 오래됨. `sudo softwareupdate --install "Command Line Tools for Xcode 26.5-26.5"` |
| ⌘⌘ 눌러도 팝업 안 뜸 | 손쉬운 사용 권한 없음. 시스템 설정 → 손쉬운 사용에서 추가 후 앱 재실행 |
| "선택된 텍스트가 없습니다" | Preview에서 드래그 선택 후 ⌘⌘. 합성 ⌘C 실패 시 손쉬운 사용 권한 확인 |
| `Gemini API 오류 (403)` | API 키 무효. Settings에서 재입력 |
| `Gemini API 오류 (429)` | 요청 한도 초과. 잠시 후 재시도하거나 더 가벼운 모델로 |

## 라이선스

MIT. `LICENSE` 참고.

## 기여

이슈/PR 환영. 큰 변경은 먼저 이슈로 의논해주세요.
