# Changelog

All notable changes to Barq are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.2.0] — 2026-07-06

Full feature parity with prateek-term, plus a set of modern and AI-native
capabilities. 127 tests across 21 suites.

### Added — parity
- **OSC 7 working-directory tracking** — local tabs title themselves by folder and remember their cwd
- **Live theming** — theme/font changes restyle every open terminal instantly
- **Middle-click paste**, **tab context menu** (rename, close others, split), **⌘F find** (SwiftTerm find bar)
- **Profile import/export** (JSON) and **ssh-config import/export** (`~/.ssh/config`)
- **Cloudflare Access** — zero-trust SSH via `cloudflared` ProxyCommand
- **Chrome SOCKS proxy launcher** with All / Include (PAC) / Exclude (bypass-list) filtering, one-click from the sidebar
- **Session restore** — reopens your tabs (and local working directories) on relaunch

### Added — modern
- **Global search (⇧⌘F)** across every open session's scrollback with jump-to-result
- **Snippets library** — reusable commands with `${VAR}` placeholders and `${BARQ:NAME}` vault refs
- **Broadcast input** — mirror keystrokes to every pane in a tab
- **Drag-and-drop SCP upload** — drop files onto an SSH terminal to upload to its cwd
- **SFTP session tabs** — "Open SFTP" from any SSH profile
- **Session recording** — export sessions to asciinema v2 `.cast`
- **Tear-off windows** — move any pane into its own window
- **`barq://` URL scheme** (connect / open / ssh) and Finder "Open folder in Barq"
- **App icon**

### Added — AI & agents
- **Command guardrails** — destructive agent commands (rm -rf, mkfs, force push, DB drops, pipe-to-shell…) require native approval
- **`run_on_tag` fleet tool** — run one command across every AI-allowed host with a tag, aggregated results

## [0.1.0] — 2026-07-06

Initial native Swift build.

- SwiftTerm terminal (Metal renderer), tabs, split panes, command palette, 6 themes
- SSH (jump hosts, port forwarding, legacy SCP), serial, telnet, local shells
- **Context Vault** — Keychain-backed variables with open/approval/secret agent policies and `${BARQ:NAME}` expansion
- **MCP server** (`barq-mcp`) with 16 tools over a same-user Unix-socket bridge
- **Local-first AI** — Ollama default, OpenRouter option; ⌘K composer, AI panel, explain-output
- All secrets in the macOS Keychain
