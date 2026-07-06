import SwiftUI

/// ⌘K: natural language → command, inserted into the focused terminal.
struct CommandComposerView: View {
    @ObservedObject var state: AppState
    @State private var instruction = ""
    @State private var suggestion: String?
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                TextField("Describe what you want to do…", text: $instruction)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onSubmit(generate)
                if busy {
                    ProgressView().controlSize(.small)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            if let suggestion {
                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
                    HStack {
                        Button {
                            run(suggestion, execute: true)
                        } label: {
                            Label("Run  ⏎", systemImage: "play.fill")
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        Button {
                            run(suggestion, execute: false)
                        } label: {
                            Label("Insert", systemImage: "text.insert")
                        }
                        Spacer()
                        Text(AIService.shared.providerLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("AI turns your words into a command for the focused terminal. ⏎ to generate, ⎋ to dismiss.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(radius: 24, y: 8)
        .onAppear { fieldFocused = true }
        .onExitCommand { state.composerVisible = false }
    }

    private func generate() {
        let text = instruction.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !busy else { return }
        busy = true
        errorText = nil
        // If a suggestion is showing, Enter runs it via the keyboardShortcut
        // on the Run button; this path only fires while the field has focus.
        Task {
            defer { busy = false }
            do {
                suggestion = try await AIService.shared.generateCommand(instruction: text, session: state.focusedSession)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func run(_ command: String, execute: Bool) {
        state.focusedSession?.send(command + (execute ? "\n" : ""))
        state.composerVisible = false
    }
}
