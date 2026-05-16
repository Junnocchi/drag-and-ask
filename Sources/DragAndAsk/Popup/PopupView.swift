import SwiftUI

struct PopupView: View {
    @ObservedObject var vm: PopupViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let err = vm.topErrorMessage {
                topErrorView(err)
                Divider()
            }
            chatList
            Divider()
            followUpBar
        }
        .frame(minWidth: 320, minHeight: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .background(KeyCatcher(onEscape: onClose))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "text.book.closed")
                Text(vm.sourceFile.isEmpty ? "drag & ask" : vm.sourceFile)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !vm.turns.isEmpty {
                    Button {
                        vm.resetConversation()
                    } label: {
                        Label("새 대화", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("이 논문의 대화 기록을 지웁니다")
                }
                Text("ESC로 닫기").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text(AIService.currentProvider.displayName)
                Text("·")
                Text(AIService.currentModel)
                    .font(.system(.caption, design: .monospaced))
                if vm.userTurnCount > 0 {
                    Text("·")
                    Text("\(vm.userTurnCount)개 질문")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                let provider = AIService.currentProvider
                if let q = vm.quota, vm.quotaProvider == provider {
                    Text(QuotaFormat.short(q))
                } else if provider == .gemini {
                    Text("Gemini는 헤드리스 quota 노출 없음")
                } else {
                    Text("quota 아직 미수집 — 새로고침")
                }
                if provider != .gemini {
                    if vm.quotaRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button {
                            vm.refreshQuota(for: provider)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(provider == .codex ? "Codex quota 조회 (약 5초)" : "Claude quota 조회 (약 20초)")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func topErrorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if vm.turns.isEmpty {
                        Text("Preview에서 텍스트를 선택하고 ⌘⌘를 누르면 여기에 대화가 쌓입니다.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(vm.turns) { turn in
                        TurnBubble(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: vm.turns.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = vm.turns.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var followUpBar: some View {
        HStack(spacing: 8) {
            TextField("후속 질문… (자세하게 라고 쓰면 길게 답함)", text: $vm.followUp)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isLoading)
                .onSubmit { vm.askFollowUp() }
            Button("Ask") { vm.askFollowUp() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(vm.isLoading || vm.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Chat bubble

struct TurnBubble: View {
    let turn: DisplayTurn

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            switch turn.kind {
            case .userSelection:
                Spacer(minLength: 20)
                userSelectionBubble
            case .userQuestion:
                Spacer(minLength: 20)
                userQuestionBubble
            case .modelReply:
                modelBubble(content: AnyView(RichResponseView(raw: turn.text)))
                Spacer(minLength: 16)
            case .modelLoading:
                modelBubble(content: AnyView(
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("분석 중…").foregroundStyle(.secondary)
                    }
                ))
                Spacer(minLength: 16)
            case .modelError(let message):
                modelBubble(content: AnyView(
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .textSelection(.enabled)
                ))
                Spacer(minLength: 16)
            }
        }
    }

    private var userSelectionBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("선택", systemImage: "text.cursor")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
            Text(turn.text)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var userQuestionBubble: some View {
        Text(turn.text)
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func modelBubble(content: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(AIService.currentProvider.displayName, systemImage: "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)
            content
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Markdown text renderer

struct MarkdownText: View {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    private enum Block: Hashable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case codeBlock(String)
    }

    private func blocks() -> [Block] {
        var result: [Block] = []
        var inCode = false
        var codeBuffer = ""
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                result.append(.paragraph(paragraphBuffer.joined(separator: " ")))
                paragraphBuffer.removeAll()
            }
        }

        for rawLine in raw.components(separatedBy: "\n") {
            let line = rawLine
            if inCode {
                if line.hasPrefix("```") {
                    result.append(.codeBlock(codeBuffer))
                    codeBuffer = ""
                    inCode = false
                } else {
                    codeBuffer += (codeBuffer.isEmpty ? "" : "\n") + line
                }
                continue
            }
            if line.hasPrefix("```") {
                flushParagraph()
                inCode = true
                continue
            }
            if line.hasPrefix("### ") {
                flushParagraph()
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
            } else {
                paragraphBuffer.append(line)
            }
        }
        flushParagraph()
        if inCode && !codeBuffer.isEmpty { result.append(.codeBlock(codeBuffer)) }
        return result
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(attributed(text))
                .font(level == 1 ? .title2 : (level == 2 ? .title3 : .headline))
                .padding(.top, 4)
        case .paragraph(let text):
            Text(attributed(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(attributed(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - ESC catcher

struct KeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = KeyCatcherView()
        v.onEscape = onEscape
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatcherView)?.onEscape = onEscape
    }

    final class KeyCatcherView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // ESC
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
