import SwiftUI

/// Snippets library: reusable commands with `${VAR}` placeholders.
struct SnippetsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: SnippetStore
    @State private var editing: Snippet?
    @State private var showingEditor = false

    init(state: AppState) {
        self.state = state
        self.store = state.snippets
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Snippets")
                        .font(.title3.bold())
                    Text("Reusable commands. Use ${NAME} for fill-in placeholders and ${BARQ:NAME} for vault values.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editing = nil
                    showingEditor = true
                } label: {
                    Label("New Snippet", systemImage: "plus")
                }
            }
            .padding()

            if store.snippets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No snippets yet")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.snippets) { snippet in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snippet.title.isEmpty ? snippet.command : snippet.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(snippet.command)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Run") { runSnippet(snippet) }
                                .buttonStyle(.borderless)
                                .disabled(state.focusedSession == nil)
                        }
                        .contextMenu {
                            Button("Run") { runSnippet(snippet) }
                            Button("Edit…") { editing = snippet; showingEditor = true }
                            Button("Delete", role: .destructive) { store.remove(id: snippet.id) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .sheet(isPresented: $showingEditor) {
            SnippetEditor(store: store, snippet: editing)
        }
    }

    private func runSnippet(_ snippet: Snippet) {
        let placeholders = snippet.placeholders
        if placeholders.isEmpty {
            state.runSnippet(snippet.command)
        } else {
            var values: [String: String] = [:]
            for name in placeholders {
                let alert = NSAlert()
                alert.messageText = "Value for ${\(name)}"
                let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
                alert.accessoryView = field
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
                alert.window.initialFirstResponder = field
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                values[name] = field.stringValue
            }
            state.runSnippet(snippet.filled(with: values))
        }
    }
}

private struct SnippetEditor: View {
    @ObservedObject var store: SnippetStore
    let snippet: Snippet?
    @State private var draft: Snippet
    @Environment(\.dismiss) private var dismiss

    init(store: SnippetStore, snippet: Snippet?) {
        self.store = store
        self.snippet = snippet
        _draft = State(initialValue: snippet ?? Snippet())
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $draft.title)
                TextField("Command", text: $draft.command, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...6)
                TextField("Tags (comma-separated)", text: Binding(
                    get: { draft.tags.joined(separator: ", ") },
                    set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
                if !draft.placeholders.isEmpty {
                    Text("Placeholders: \(draft.placeholders.map { "${\($0)}" }.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(snippet == nil ? "Add" : "Save") {
                    store.upsert(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 320)
    }
}
