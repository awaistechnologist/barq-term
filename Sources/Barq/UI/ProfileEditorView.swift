import SwiftUI
import AppKit

/// Create/edit sheet for connection profiles.
struct ProfileEditorView: View {
    @ObservedObject var state: AppState
    @State private var draft: ConnectionProfile
    @State private var password = ""
    @State private var pemText = ""
    @State private var tagsText = ""
    @State private var sshOptionsText = ""
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool

    init(state: AppState, profile: ConnectionProfile?) {
        self.state = state
        let initial = profile ?? ConnectionProfile()
        _draft = State(initialValue: initial)
        _tagsText = State(initialValue: initial.tags.joined(separator: ", "))
        _sshOptionsText = State(initialValue: initial.extraSSHOptions.joined(separator: "\n"))
        isNew = profile == nil
        if let profile {
            if profile.authType == .password {
                _password = State(initialValue: Keychain.get(profile.passwordKeychainKey) ?? "")
            }
            if profile.authType == .keyText {
                _pemText = State(initialValue: Keychain.get(profile.pemTextKeychainKey) ?? "")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New Profile" : "Edit Profile")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ProfileKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("Tags (comma-separated)", text: $tagsText)
                }

                switch draft.kind {
                case .ssh:
                    Section("Connection") {
                        TextField("Host", text: $draft.host)
                        TextField("Port", value: $draft.port, format: .number)
                        TextField("Username", text: $draft.username)
                        Picker("Authentication", selection: $draft.authType) {
                            ForEach(AuthType.allCases) { auth in
                                Text(auth.label).tag(auth)
                            }
                        }
                        if draft.authType == .password {
                            SecureField("Password (stored in Keychain)", text: $password)
                        }
                        if draft.authType == .key {
                            HStack {
                                TextField("Identity file (~/.ssh/id_ed25519)", text: $draft.identityFile)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse…") { browseForKey() }
                            }
                            Text("Pick or type the path to your private key. Passphrase-protected keys will prompt in the terminal.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        if draft.authType == .keyText {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Paste your private key (stored in the Keychain, never on disk in plaintext):")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $pemText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(height: 90)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
                            }
                        }
                        Toggle("Forward SSH agent (-A)", isOn: $draft.agentForward)
                        Toggle("Legacy SCP (dropbear / BusyBox)", isOn: $draft.legacySCP)
                    }
                    Section("Advanced SSH options") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("One -o option per line, e.g. StrictHostKeyChecking=no")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            TextEditor(text: $sshOptionsText)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 60)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
                        }
                    }
                    Section("Cloudflare Access") {
                        Toggle("Tunnel via cloudflared (zero-trust)", isOn: $draft.cloudflareAccess)
                            .onChange(of: draft.cloudflareAccess) { on in
                                if on { draft.jumpHost.enabled = false }
                            }
                        if draft.cloudflareAccess {
                            Text("Requires `cloudflared` installed. Uses ProxyCommand: cloudflared access ssh --hostname %h")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Jump Host") {
                        Toggle("Connect through a jump host", isOn: $draft.jumpHost.enabled)
                            .disabled(draft.cloudflareAccess)
                            .onChange(of: draft.jumpHost.enabled) { on in
                                if on { draft.cloudflareAccess = false }
                            }
                        if draft.jumpHost.enabled {
                            TextField("Jump host", text: $draft.jumpHost.host)
                            TextField("Jump port", value: $draft.jumpHost.port, format: .number)
                            TextField("Jump username", text: $draft.jumpHost.username)
                            TextField("Jump identity file (optional)", text: $draft.jumpHost.identityFile)
                        }
                    }
                    Section("Port Forwarding") {
                        ForEach($draft.portForwards) { $forward in
                            HStack {
                                Picker("", selection: $forward.kind) {
                                    ForEach(ForwardKind.allCases) { kind in
                                        Text(kind.label).tag(kind)
                                    }
                                }
                                .frame(width: 150)
                                TextField("Listen", value: $forward.listenPort, format: .number.grouping(.never))
                                    .frame(width: 60)
                                if forward.kind != .dynamic {
                                    TextField("Host", text: $forward.targetHost)
                                    TextField("Port", value: $forward.targetPort, format: .number.grouping(.never))
                                        .frame(width: 60)
                                }
                                Toggle("", isOn: $forward.enabled)
                                Button(role: .destructive) {
                                    draft.portForwards.removeAll { $0.id == forward.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this forwarding rule")
                            }
                            if forward.kind == .dynamic {
                                HStack {
                                    Picker("Chrome routing", selection: $forward.filterMode) {
                                        ForEach(ProxyFilterMode.allCases) { m in
                                            Text(m.label).tag(m)
                                        }
                                    }
                                    .frame(width: 220)
                                }
                                if forward.filterMode != .all {
                                    TextField("Hosts (comma-separated: *.corp.com, 10.0.0.0/8)", text: Binding(
                                        get: { forward.filterHosts.joined(separator: ", ") },
                                        set: { forward.filterHosts = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                                    ))
                                    .font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                        Button {
                            draft.portForwards.append(PortForward())
                        } label: {
                            Label("Add forward rule", systemImage: "plus")
                        }
                    }
                case .telnet:
                    Section("Connection") {
                        TextField("Host", text: $draft.host)
                        TextField("Port", value: $draft.port, format: .number)
                    }
                case .serial:
                    Section("Serial") {
                        Picker("Device", selection: $draft.serialDevice) {
                            Text("Choose…").tag("")
                            ForEach(SerialBackend.availablePorts(), id: \.self) { port in
                                Text(port).tag(port)
                            }
                        }
                        Picker("Baud rate", selection: $draft.baudRate) {
                            ForEach([9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600], id: \.self) { rate in
                                Text(String(rate)).tag(rate)
                            }
                        }
                        Picker("Data bits", selection: $draft.dataBits) {
                            ForEach([7, 8], id: \.self) { Text(String($0)).tag($0) }
                        }
                        Picker("Stop bits", selection: $draft.stopBits) {
                            ForEach([1, 2], id: \.self) { Text(String($0)).tag($0) }
                        }
                        Picker("Parity", selection: $draft.parity) {
                            ForEach(["none", "even", "odd"], id: \.self) { Text($0).tag($0) }
                        }
                    }
                case .local:
                    Section("Local") {
                        TextField("Working directory (optional)", text: $draft.workingDirectory)
                    }
                }

                Section("Custom Actions") {
                    ForEach($draft.customActions) { $action in
                        HStack {
                            TextField("Name", text: $action.name)
                                .frame(width: 140)
                            TextField("Command", text: $action.command)
                                .font(.system(.body, design: .monospaced))
                            Button(role: .destructive) {
                                draft.customActions.removeAll { $0.id == action.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this action")
                        }
                    }
                    Button {
                        draft.customActions.append(CustomAction())
                    } label: {
                        Label("Add action", systemImage: "plus")
                    }
                }

                Section {
                    Toggle("Allow AI agents to use this profile", isOn: $draft.aiAllowed)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 620, height: 640)
    }

    private func save() {
        draft.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        draft.extraSSHOptions = sshOptionsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        state.profiles.upsert(draft)
        // Persist secrets to the Keychain according to the chosen auth mode.
        state.profiles.setPassword(draft.authType == .password ? password : nil, for: draft)
        state.profiles.setPemText(draft.authType == .keyText ? pemText : nil, for: draft)
        dismiss()
    }

    private func browseForKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.title = "Choose SSH Private Key"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            draft.identityFile = url.path
        }
    }
}
