import SwiftUI

struct SettingsView: View {
    @State private var provider: AIProvider = AIService.currentProvider
    @State private var model: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var isTesting = false
    @State private var testOutput: String = ""

    enum TestStatus {
        case idle
        case ok
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                activeSummary
                Divider()
                providerSection
                modelSection
                actionRow
                statusLine
                Divider()
                authHelpSection
            }
            .padding(20)
        }
        .frame(minWidth: 600, idealWidth: 660, minHeight: 600, idealHeight: 820)
        .onAppear { reloadModelForProvider() }
        .onChange(of: provider) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: AIService.providerDefaultsKey)
            reloadModelForProvider()
            testStatus = .idle
            testOutput = ""
        }
    }

    /// Big banner at the top showing whatever is currently persisted in UserDefaults
    /// — i.e. what ⌘⌘ will actually use, regardless of unsaved field edits.
    private var activeSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("현재 활성").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(AIService.currentProvider.displayName)
                        .font(.headline)
                    Text("·").foregroundStyle(.secondary)
                    Text(AIService.currentModel)
                        .font(.system(.headline, design: .monospaced))
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Provider").font(.headline)
            Picker("", selection: $provider) {
                ForEach(AIProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("모델").font(.headline)
                TextField("model id", text: $model)
                    .textFieldStyle(.roundedBorder)
                Menu("프리셋") {
                    ForEach(provider.modelPresets, id: \.self) { preset in
                        Button(preset.label) { model = preset.value }
                    }
                }
                .frame(maxWidth: 90)
            }
            Text("프로바이더별로 모델 설정이 따로 저장됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack {
            Button("저장") {
                UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines),
                                           forKey: provider.modelDefaultsKey)
                testStatus = .idle
                testOutput = ""
            }

            Button("연결 테스트") {
                Task { await runTest() }
            }
            .disabled(isTesting)

            if isTesting {
                ProgressView().controlSize(.small)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .ok:
            Label("연결 성공 — \(testOutput.prefix(80))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    private var authHelpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLI 설치 및 인증").font(.headline)

            ForEach(AIProvider.allCases, id: \.self) { p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: p == provider ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p == provider ? .green : .secondary)
                        Text(p.displayName).font(.subheadline.bold())
                    }
                    ForEach(Array(p.setupSteps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(idx + 1).").foregroundStyle(.secondary)
                            Text(step)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .padding(.bottom, 6)
            }

            Text("사용법").font(.headline).padding(.top, 8)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Preview에서 PDF를 엽니다.")
                Text("2. 본문에서 텍스트를 드래그로 선택합니다.")
                Text("3. ⌘ 키를 두 번 빠르게 누릅니다.")
                Text("4. 팝업에서 한국어 해설을 확인합니다. 후속 질문도 가능합니다.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func reloadModelForProvider() {
        model = UserDefaults.standard.string(forKey: provider.modelDefaultsKey) ?? provider.defaultModel
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        UserDefaults.standard.set(provider.rawValue, forKey: AIService.providerDefaultsKey)
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines),
                                   forKey: provider.modelDefaultsKey)
        do {
            let result = try await AIService.connectionTest()
            if result.isEmpty {
                testStatus = .failed("빈 응답")
            } else {
                testOutput = result
                testStatus = .ok
            }
        } catch {
            testStatus = .failed(error.localizedDescription)
        }
    }
}
