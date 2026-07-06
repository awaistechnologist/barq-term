<h1 align="center">⚡ Barq</h1>

<p align="center">
  <strong>The AI-native macOS terminal. Native Swift. Zero lag. Built for agents.</strong>
</p>

<p align="center">
  <em>برق — "lightning", and the old Arabic word for the telegraph:<br>commands carried over wires to distant machines. That's what Barq does, with an AI operator.</em>
</p>

---

Barq is a modern terminal emulator and connection manager for macOS, written in **pure Swift** (SwiftUI + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) with Metal GPU rendering). No Electron, no web views, no lag.

It is built AI-first around three ideas:

1. **Agents are users too.** Barq ships an MCP server — any AI agent (Claude Desktop, Claude Code, any MCP client) can discover your hosts, open sessions, run commands, and transfer files, gated by per-profile permission chips.
2. **The Context Vault.** A system-wide store for the variables that make up your working context — device IPs, endpoints, tokens, deploy keys. Values live in the macOS Keychain. Agents can *discover* every variable, but what they can *read* is your call, per variable: **open**, **ask-me-first**, or **secret** — where secrets are *usable* inside commands (`${BARQ:DEPLOY_KEY}`) but never revealed in plaintext. Every agent access is audited.
3. **Local-first AI.** The built-in assistant runs on **Ollama** by default — private, free, on your machine. Drop in an **OpenRouter** key to use frontier models instead. ⌘K turns plain English into commands; the AI panel sees your session and explains failures.

## Features

### Terminal
- Native SwiftTerm emulator, true color, Metal GPU renderer
- Tabs, **split panes** (⌘D / ⇧⌘D), multiple windows
- **Command palette** (⇧⌘P) with fuzzy search over every action and host
- 6 built-in themes (Catppuccin Mocha/Latte, Dracula, Nord, Tokyo Night, Solarized Dark)

### Connections
- **SSH** — agent/password/key auth, jump hosts (ProxyJump), port forwarding (-L/-R/-D SOCKS5), keep-alives, legacy SCP mode for BusyBox/dropbear devices
- **Serial** — raw termios, all baud rates, data/stop bits, parity
- **Telnet** — built-in client with IAC negotiation (no system telnet needed)
- **Local shells**, login-shell semantics
- Profiles with tags, sidebar grouping, search, custom per-profile actions, JSON import/export
- Passwords and keys never touch disk in plaintext — everything is Keychain-backed

### AI
- **⌘K composer** — describe what you want; get the command; run or insert it
- **AI panel** (⇧⌘A) — chat with full session context; proposed commands are one-click runnable
- **⌘E** — explain the last output/error
- Ollama auto-detection, or OpenRouter with any model id

### MCP — 16 tools for agents

`list_profiles` · `add_profile` · `remove_profile` · `connect` · `list_sessions` · `get_status` · `run_command` · `send_input` · `read_output` · `disconnect` · `list_serial_ports` · `upload_file` · `download_file` · `vault_list` · `vault_get` · `vault_set`

Safety model:
- Agents can only connect to profiles whose **AI chip** you switched on
- Agent-created profiles start with AI access **off**
- Vault reads honor per-variable policy; **secret** values are substituted into commands server-side and never returned to the agent
- Full audit log of every agent access in the Vault window

## Quick start

```bash
git clone https://github.com/YOUR_USER/barq && cd barq
swift run Barq            # run it
./scripts/make-app.sh     # or build dist/Barq.app
```

Register the MCP server (Settings → MCP → one click), or manually:

```bash
claude mcp add barq /path/to/Barq.app/Contents/MacOS/barq-mcp
```

For local AI: install [Ollama](https://ollama.com), `ollama pull llama3.2`, done — Barq finds it automatically.

## Example: an agent using the vault

```
You (to Claude): "Check disk usage on the staging box"

Claude → vault_list                     # discovers STAGING_IP ("staging server address", open)
Claude → connect(profile_name: "staging")
Claude → run_command(session_id: "1",
           command: "df -h ${BARQ:STAGING_IP}...")   # Barq expands the variable
```

If the variable were policy `approval`, you'd get a native prompt before the read; if `secret`, the agent could use it but never see it.

## Development

TDD is the house style — the logic layer is fully covered and the suite runs in ~2s:

```bash
./scripts/test.sh                      # full suite (66 tests / 10 suites)
./scripts/test.sh --filter VaultStore  # one suite
swift build                            # app + barq-mcp
```

Requirements: macOS 13+, Swift 6 toolchain (Command Line Tools are enough — no Xcode needed).

## Roadmap

- [ ] Developer ID signing + notarization, Homebrew cask
- [ ] Block-based output (AI-addressable command/output units)
- [ ] Session persistence across app restarts
- [ ] Fleet operations: run across all hosts with a tag; runbooks
- [ ] SFTP browser panel, session recording/replay
- [ ] Guardrail policies for agent-run commands (allowlists, read-only mode, approval gates)

## License

MIT
