import Foundation
import Darwin

// barq-mcp — MCP stdio server for the Barq terminal.
//
// Speaks MCP JSON-RPC (newline-delimited) on stdin/stdout and proxies every
// tool call to the running Barq app over its Unix-socket bridge. If Barq is
// not running, tool calls return a helpful error instead of failing silently.

// MARK: - Bridge client

final class BridgeClient {
    private var fd: Int32 = -1
    private var inbox = Data()

    var socketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Barq/bridge.sock").path
    }

    private func connectIfNeeded() -> Bool {
        if fd >= 0 { return true }
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let ok = withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr -> Bool in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                socketPath.withCString { src in
                    guard strlen(src) < capacity else { return false }
                    strcpy(dest, src)
                    return true
                }
            }
        }
        guard ok else { close(sock); return false }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, size) }
        }
        guard connected == 0 else { close(sock); return false }
        fd = sock
        return true
    }

    private func disconnect() {
        if fd >= 0 { close(fd) }
        fd = -1
        inbox.removeAll()
    }

    /// Synchronous round-trip; single request in flight at a time (MCP stdio
    /// clients serialize tool calls, and the bridge answers by request id).
    func call(method: String, params: [String: Any]) throws -> Any {
        guard connectIfNeeded() else {
            throw BarqMCPError.appNotRunning
        }
        let request: [String: Any] = ["id": Int.random(in: 1...1_000_000), "method": method, "params": params]
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(0x0A)

        let sent = data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        guard sent else {
            disconnect()
            throw BarqMCPError.appNotRunning
        }

        // Read one line (responses are serialized per connection).
        var buf = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if let newline = inbox.firstIndex(of: 0x0A) {
                let line = inbox.prefix(upTo: newline)
                inbox.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                    throw BarqMCPError.protocolError
                }
                if let error = object["error"] as? String {
                    throw BarqMCPError.bridge(error)
                }
                return object["result"] ?? NSNull()
            }
            let n = read(fd, &buf, buf.count)
            if n <= 0 {
                disconnect()
                throw BarqMCPError.appNotRunning
            }
            inbox.append(contentsOf: buf[0..<n])
        }
        disconnect()
        throw BarqMCPError.timeout
    }
}

enum BarqMCPError: LocalizedError {
    case appNotRunning
    case protocolError
    case timeout
    case bridge(String)

    var errorDescription: String? {
        switch self {
        case .appNotRunning:
            return "The Barq app is not running. Ask the user to launch Barq, then retry."
        case .protocolError:
            return "Malformed response from the Barq bridge."
        case .timeout:
            return "Timed out waiting for the Barq app."
        case .bridge(let message):
            return message
        }
    }
}

// MARK: - Tool definitions

struct ToolDef {
    let name: String
    let description: String
    let schema: [String: Any]

    var json: [String: Any] {
        ["name": name, "description": description, "inputSchema": schema]
    }
}

func obj(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
    ["type": "object", "properties": properties, "required": required]
}

func str(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
func int(_ description: String) -> [String: Any] { ["type": "integer", "description": description] }
func bool(_ description: String) -> [String: Any] { ["type": "boolean", "description": description] }

let tools: [ToolDef] = [
    ToolDef(name: "list_profiles",
            description: "List saved connection profiles in Barq (SSH, serial, telnet, local shell) with their AI-access status.",
            schema: obj([:])),
    ToolDef(name: "add_profile",
            description: "Create a new connection profile in Barq. New profiles have AI access OFF until the user enables it.",
            schema: obj([
                "name": str("Unique profile name"),
                "kind": ["type": "string", "enum": ["ssh", "serial", "telnet", "local"], "description": "Connection kind (default ssh)"],
                "host": str("Hostname or IP (ssh/telnet)"),
                "port": int("TCP port (default 22)"),
                "username": str("SSH username"),
                "identity_file": str("Path to SSH private key"),
                "serial_device": str("Serial device path, e.g. /dev/cu.usbserial-0001"),
                "baud_rate": int("Serial baud rate (default 115200)"),
                "tags": str("Comma-separated tags, e.g. LAB,ROUTERS")
            ], required: ["name"])),
    ToolDef(name: "remove_profile",
            description: "Delete a connection profile by name. Refuses if the profile has active sessions unless force=true.",
            schema: obj(["name": str("Profile name"), "force": bool("Force removal with active sessions")], required: ["name"])),
    ToolDef(name: "connect",
            description: "Open a terminal session for a saved profile (must have AI access enabled). Returns a session_id.",
            schema: obj(["profile_name": str("Name of the profile to connect")], required: ["profile_name"])),
    ToolDef(name: "list_sessions",
            description: "List active terminal sessions with their ids, profiles and status.",
            schema: obj([:])),
    ToolDef(name: "get_status",
            description: "Get the status of a session (connecting/connected/exited) and its current directory if known.",
            schema: obj(["session_id": str("Session id")], required: ["session_id"])),
    ToolDef(name: "run_command",
            description: "Run a shell command in a session and wait for its output and exit code. Supports Context Vault expansion: ${BARQ:NAME} references are resolved by Barq (secret values are substituted server-side and never shown to you).",
            schema: obj([
                "session_id": str("Session id"),
                "command": str("Command to execute. May reference vault variables as ${BARQ:NAME}."),
                "timeout": int("Seconds to wait (default 30)")
            ], required: ["session_id", "command"])),
    ToolDef(name: "send_input",
            description: "Send raw input to a session without waiting (for interactive prompts, confirmations). Supports ${BARQ:NAME} vault expansion.",
            schema: obj(["session_id": str("Session id"), "text": str("Text to send; include \\n to press Enter")], required: ["session_id", "text"])),
    ToolDef(name: "read_output",
            description: "Read the most recent output from a session (ANSI-stripped).",
            schema: obj(["session_id": str("Session id"), "max_bytes": int("Max bytes to return (default 8192)")], required: ["session_id"])),
    ToolDef(name: "disconnect",
            description: "Close a terminal session.",
            schema: obj(["session_id": str("Session id")], required: ["session_id"])),
    ToolDef(name: "list_serial_ports",
            description: "List serial devices available on this Mac (/dev/cu.*, /dev/tty.*).",
            schema: obj([:])),
    ToolDef(name: "upload_file",
            description: "Upload a local file to a remote host over SCP using a profile's settings (key auth required).",
            schema: obj([
                "profile_name": str("SSH profile name"),
                "local_path": str("Local file path"),
                "remote_path": str("Destination path on the remote host")
            ], required: ["profile_name", "local_path", "remote_path"])),
    ToolDef(name: "download_file",
            description: "Download a remote file to the local machine over SCP using a profile's settings (key auth required).",
            schema: obj([
                "profile_name": str("SSH profile name"),
                "local_path": str("Local destination path"),
                "remote_path": str("Remote file path")
            ], required: ["profile_name", "local_path", "remote_path"])),
    ToolDef(name: "vault_list",
            description: "Discover Context Vault variables: names, descriptions, and read policies. Values are never included. Reference any variable in commands as ${BARQ:NAME}.",
            schema: obj([:])),
    ToolDef(name: "vault_get",
            description: "Read a Context Vault variable's value. Honors the variable's policy: open variables return immediately, approval variables prompt the user, secret variables always refuse (use them via ${BARQ:NAME} in run_command instead).",
            schema: obj(["name": str("Variable name (UPPER_SNAKE_CASE)")], required: ["name"])),
    ToolDef(name: "vault_set",
            description: "Store or update a Context Vault variable so other agents and the user can reuse it. Policy defaults to open.",
            schema: obj([
                "name": str("Variable name (UPPER_SNAKE_CASE)"),
                "value": str("Value to store (kept in the macOS Keychain)"),
                "description": str("What this variable is, for discovery"),
                "policy": ["type": "string", "enum": ["open", "approval", "secret"], "description": "Read policy (default open)"]
            ], required: ["name", "value"]))
]

// MARK: - MCP stdio loop

let bridge = BridgeClient()
let stdout = FileHandle.standardOutput

func send(_ object: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
    data.append(0x0A)
    stdout.write(data)
}

func reply(id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func replyError(id: Any, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func textResult(_ text: String, isError: Bool = false) -> [String: Any] {
    ["content": [["type": "text", "text": text]], "isError": isError]
}

func handle(request: [String: Any]) {
    let method = request["method"] as? String ?? ""
    let id = request["id"]

    // Notifications (no id) need no response.
    guard let id else { return }

    switch method {
    case "initialize":
        let params = request["params"] as? [String: Any]
        let requested = params?["protocolVersion"] as? String ?? "2024-11-05"
        reply(id: id, result: [
            "protocolVersion": requested,
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "barq", "version": "0.1.0"],
            "instructions": """
            Barq is a macOS terminal with SSH, serial, telnet and local shell sessions, \
            plus a Context Vault of user-managed variables. Start with list_profiles and \
            vault_list to discover what you can use. Reference vault variables in commands \
            as ${BARQ:NAME} — secrets are expanded by Barq without being revealed to you.
            """
        ])
    case "ping":
        reply(id: id, result: [:])
    case "tools/list":
        reply(id: id, result: ["tools": tools.map(\.json)])
    case "resources/list":
        reply(id: id, result: ["resources": [] as [Any]])
    case "prompts/list":
        reply(id: id, result: ["prompts": [] as [Any]])
    case "tools/call":
        let params = request["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        guard tools.contains(where: { $0.name == name }) else {
            reply(id: id, result: textResult("Unknown tool: \(name)", isError: true))
            return
        }
        do {
            let result = try bridge.call(method: name, params: arguments)
            if let text = result as? String {
                reply(id: id, result: textResult(text))
            } else if JSONSerialization.isValidJSONObject(result),
                      let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                reply(id: id, result: textResult(String(decoding: data, as: UTF8.self)))
            } else {
                reply(id: id, result: textResult(String(describing: result)))
            }
        } catch {
            reply(id: id, result: textResult(error.localizedDescription, isError: true))
        }
    default:
        replyError(id: id, code: -32601, message: "Method not found: \(method)")
    }
}

// Read newline-delimited JSON-RPC from stdin until EOF.
setvbuf(Darwin.stdout, nil, _IONBF, 0)
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    handle(request: request)
}
