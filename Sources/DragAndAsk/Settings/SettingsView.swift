import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = KeychainHelper.loadAPIKey() ?? ""
    @State private var model: String = UserDefaults.standard.string(forKey: GeminiService.modelDefaultsKey) ?? GeminiService.defaultModel
    @State private var testStatus: TestStatus = .idle
    @State private var isTesting = false

    private let modelPresets: [String] = [
        "gemini-3-pro-preview",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.0-flash"
    ]

    enum TestStatus {
        case idle
        case ok
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gemini API 키")
                .font(.headline)

            SecureField("AIza…", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Text("모델").font(.headline)
                TextField("gemini-…", text: $model)
                    .textFieldStyle(.roundedBorder)
                Menu("프리셋") {
                    ForEach(modelPresets, id: \.self) { name in
                        Button(name) { model = name }
                    }
                }
                .frame(maxWidth: 90)
            }

            HStack {
                Button("저장") {
                    KeychainHelper.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: GeminiService.modelDefaultsKey)
                    testStatus = .idle
                }
                .disabled(apiKey.isEmpty)

                Button("연결 테스트") {
                    Task { await runTest() }
                }
                .disabled(apiKey.isEmpty || isTesting)

                if isTesting {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Link("키 발급 받기", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.footnote)
            }

            switch testStatus {
            case .idle:
                EmptyView()
            case .ok:
                Label("연결 성공", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("사용법").font(.headline)
                Text("1. Preview에서 PDF를 엽니다.")
                Text("2. 본문에서 텍스트를 드래그로 선택합니다.")
                Text("3. ⌘ 키를 두 번 빠르게 누릅니다.")
                Text("4. 팝업에서 한국어 해석을 확인합니다.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 420, idealHeight: 440)
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        KeychainHelper.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: GeminiService.modelDefaultsKey)
        do {
            let result = try await GeminiService.connectionTest()
            testStatus = result.isEmpty ? .failed("빈 응답") : .ok
        } catch {
            testStatus = .failed(error.localizedDescription)
        }
    }
}
