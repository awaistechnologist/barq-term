import SwiftUI

/// Context Vault manager: variables, policies, and the agent audit trail.
struct VaultView: View {
    @ObservedObject var vault: VaultStore
    @State private var showingEditor = false
    @State private var editing: VaultItem?
    @State private var revealed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Context Vault")
                        .font(.title3.bold())
                    Text("Variables AI agents can discover — you decide what they can read. Values live in the macOS Keychain. Use them anywhere as ${BARQ:NAME}.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editing = nil
                    showingEditor = true
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
            }
            .padding()

            if vault.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "key.viewfinder")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No variables yet")
                        .font(.headline)
                    Text("Store device IPs, endpoints, and tokens once — reuse them in any\nterminal or let AI agents use them under your policy.")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vault.items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.policy.symbol)
                                .foregroundStyle(item.policy == .secret ? .red : (item.policy == .approval ? .orange : .green))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    Text(item.policy.label)
                                        .font(.system(size: 9, weight: .medium))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                                        .foregroundStyle(.secondary)
                                }
                                if !item.summary.isEmpty {
                                    Text(item.summary)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(revealed.contains(item.name) ? (vault.value(of: item.name) ?? "") : "••••••••")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 200, alignment: .trailing)
                            Button {
                                if revealed.contains(item.name) { revealed.remove(item.name) } else { revealed.insert(item.name) }
                            } label: {
                                Image(systemName: revealed.contains(item.name) ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                        .contextMenu {
                            Button("Edit…") {
                                editing = item
                                showingEditor = true
                            }
                            Button("Copy ${BARQ:\(item.name)}") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("${BARQ:\(item.name)}", forType: .string)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                vault.remove(name: item.name)
                            }
                        }
                    }
                }
            }

            Divider()

            DisclosureGroup {
                if vault.auditLog.isEmpty {
                    Text("No agent access yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(vault.auditLog.reversed()) { entry in
                                HStack(spacing: 8) {
                                    Image(systemName: entry.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(entry.allowed ? .green : .red)
                                        .font(.system(size: 10))
                                    Text(entry.date, style: .time)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text("\(entry.agent) → \(entry.action) \(entry.variable)")
                                        .font(.system(size: 11))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            } label: {
                Label("Agent access log", systemImage: "list.bullet.clipboard")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $showingEditor) {
            VaultItemEditor(vault: vault, item: editing)
        }
    }
}

private struct VaultItemEditor: View {
    @ObservedObject var vault: VaultStore
    let item: VaultItem?
    @State private var name = ""
    @State private var value = ""
    @State private var summary = ""
    @State private var policy: VaultPolicy = .approval
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name (UPPER_SNAKE_CASE)", text: $name)
                    .font(.system(.body, design: .monospaced))
                    .disabled(item != nil)
                TextField("Description (what agents see during discovery)", text: $summary)
                SecureField("Value (stored in Keychain)", text: $value)
                Picker("Agent read policy", selection: $policy) {
                    ForEach(VaultPolicy.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.system(size: 11))
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(item == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || value.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 280)
        .onAppear {
            if let item {
                name = item.name
                summary = item.summary
                policy = item.policy
                value = vault.value(of: item.name) ?? ""
            }
        }
    }

    private func save() {
        do {
            _ = try vault.set(name: name, value: value, summary: summary, policy: policy)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
