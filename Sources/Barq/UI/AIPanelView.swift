import SwiftUI

struct ChatEntry: Identifiable, Hashable {
    let id = UUID()
    let message: AIMessage
}

/// Right-hand AI chat panel with terminal context and one-click command runs.
struct AIPanelView: View {
    @ObservedObject var state: AppState
    @ObservedObject var ai = AIService.shared
    @State private var entries: [ChatEntry] = []
    @State private var input = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(ai.providerLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    entries.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Clear conversation")
            }
            .padding(10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if entries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ask about your terminal")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("The assistant sees the active session's recent output. Try “why did that fail?” or “write a command to find large files”.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Button("Explain last output (⌘E)") { explain() }
                                    .font(.system(size: 11))
                                    .disabled(state.focusedSession == nil || busy)
                            }
                            .padding(12)
                        }
                        ForEach(entries) { entry in
                            ChatBubble(entry: entry, state: state)
                                .id(entry.id)
                        }
                        if busy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: entries.count) { _ in
                    if let last = entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                TextField("Ask AI…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...4)
                    .onSubmit(sendMessage)
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(input.isEmpty || busy ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(input.isEmpty || busy)
            }
            .padding(10)
        }
        .frame(width: 300)
        .background(VisualEffect(material: .sidebar))
        .onReceive(NotificationCenter.default.publisher(for: .barqExplainRequested)) { _ in
            explain()
        }
        .onChange(of: state.pendingAIQuestion) { question in
            guard let question, !question.isEmpty else { return }
            state.pendingAIQuestion = nil
            ask(question)
        }
        .onAppear {
            if let question = state.pendingAIQuestion, !question.isEmpty {
                state.pendingAIQuestion = nil
                ask(question)
            }
        }
    }

    /// Ask a specific question (routed from the omni-bar).
    private func ask(_ question: String) {
        guard !busy else { return }
        entries.append(ChatEntry(message: AIMessage(role: .user, content: question)))
        busy = true
        let history = entries.map(\.message)
        let session = state.focusedSession
        Task {
            defer { busy = false }
            do {
                let answer = try await AIService.shared.chat(history: history, session: session)
                entries.append(ChatEntry(message: AIMessage(role: .assistant, content: answer)))
            } catch {
                entries.append(ChatEntry(message: AIMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)")))
            }
        }
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        entries.append(ChatEntry(message: AIMessage(role: .user, content: text)))
        busy = true
        let history = entries.map(\.message)
        let session = state.focusedSession
        Task {
            defer { busy = false }
            do {
                let answer = try await AIService.shared.chat(history: history, session: session)
                entries.append(ChatEntry(message: AIMessage(role: .assistant, content: answer)))
            } catch {
                entries.append(ChatEntry(message: AIMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)")))
            }
        }
    }

    func explain() {
        guard let session = state.focusedSession, !busy else { return }
        busy = true
        entries.append(ChatEntry(message: AIMessage(role: .user, content: "Explain the recent output of this session.")))
        Task {
            defer { busy = false }
            do {
                let answer = try await AIService.shared.explain(session: session)
                entries.append(ChatEntry(message: AIMessage(role: .assistant, content: answer)))
            } catch {
                entries.append(ChatEntry(message: AIMessage(role: .assistant, content: "⚠️ \(error.localizedDescription)")))
            }
        }
    }
}

/// Renders one chat message; assistant code blocks get a "run" button.
private struct ChatBubble: View {
    let entry: ChatEntry
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.message.role == .user ? "You" : "Assistant")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(entry.message.role == .user ? .blue : .purple)
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    Text(LocalizedStringKey(text))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                case .code(let code):
                    VStack(alignment: .leading, spacing: 0) {
                        Text(code)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        HStack {
                            Button {
                                state.focusedSession?.send(code.trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
                            } label: {
                                Label("Run", systemImage: "play.fill")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .disabled(state.focusedSession == nil)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(6)
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Segment {
        case text(String)
        case code(String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        let parts = entry.message.content.components(separatedBy: "```")
        for (index, part) in parts.enumerated() {
            if index % 2 == 0 {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(.text(trimmed)) }
            } else {
                // Drop a language hint on the first line if present.
                var code = part
                if let newline = code.firstIndex(of: "\n"), code[..<newline].count <= 12 {
                    code = String(code[code.index(after: newline)...])
                }
                let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(.code(trimmed)) }
            }
        }
        return result
    }
}
