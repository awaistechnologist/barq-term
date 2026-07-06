# Changelog

All notable changes to Barq are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.3.0] — 2026-07-06

Completes prateek-term feature parity with the last remaining item: **tab
groups**. 147 tests across 25 suites.

### Added
- **Tab groups** — colored, collapsible groups in the tab bar:
  - Auto-form from a profile's first connection tag (HOME, AWS, LAB, …), with a
    deterministic per-tag color (stable across launches).
  - A group's container appears once it holds two or more tabs; a lone grouped
    tab shows just its accent dot (the "groups form when they matter" behavior).
  - **Drag** tabs to reorder, to move them between groups, or onto a group to
    join it; **collapse/expand** groups; **rename** and **recolor** via the group
    header's context menu; group/ungroup and "new group from tab" from a tab's
    menu.
  - Grouping (name + color) is preserved across relaunch by session restore.

## [0.2.1] — 2026-07-06

Security & correctness pass (full code/security/docs review). 136 tests.

### Security
- **Guardrails now classify the *expanded* command.** Vault expansion runs
  before the dangerous-command check, so a destructive payload hidden in a vault
  variable can no longer smuggle past the approval prompt.
- **Secret values are redacted from all agent output.** Even if a `secret` is
  echoed by the remote shell or printed by a command, it is scrubbed from
  `run_command` / `read_output` / `run_on_tag` results before returning.
- **SSH option-injection closed.** A `--` separator guards the destination and
  hosts are validated (no leading `-`, no metacharacters), so a host like
  `-oProxyCommand=…` can't be parsed as an ssh option. `add_profile` rejects
  unsafe hosts.
- **`barq://` deep links now require confirmation** before connecting/opening,
  and ad-hoc ssh hosts are validated.
- **Keychain items are `WhenUnlockedThisDeviceOnly`** (no iCloud sync / backup);
  vault writes surface Keychain failures instead of silently succeeding.
- **Guardrail decisions and vault access are persisted** to an append-only
  on-disk audit log; support dir is `0700`; PAC host filters are JS-escaped.

### Fixed
- **Data race** on the Context Vault (agent reads ran off the main thread while
  the UI mutated it) — vault agent methods are now main-actor isolated. This
  also removes intermittent test failures.
- **`run_command` no longer returns early** on slow/quiet shell commands
  (e.g. `sleep 2 && ls`); the quiet-period fallback is limited to serial/telnet.
- Serial teardown race (double-close) and a silent telnet receive-error hang.

### Docs
- Fixed stale test count in README, corrected MCP `serverInfo` version, and
  qualified the "feature parity" claim (tab groups + FTP are intentionally out).
- Added SECURITY.md, CONTRIBUTING.md, issue/PR templates.

## [0.2.0] — 2026-07-06

Near-complete feature parity with prateek-term, plus a set of modern and
AI-native capabilities. 127 tests across 21 suites.

> Two prateek-term features are intentionally not carried over: **tab groups**
> (tracked on the roadmap) and the **interactive FTP client** (modern macOS
> ships no `ftp` binary; use SFTP instead).

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
