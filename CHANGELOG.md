# Changelog

All notable changes to Barq are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.7.1] — 2026-07-08

Polish, a critical rendering fix, local-AI setup, and the release pipeline.
184 tests across 32 suites.

### Fixed
- **Terminals rendered blank** — SwiftTerm's Metal path drew nothing on some
  GPUs (the buffer filled but didn't paint). Forced CoreGraphics rendering.
- **Keyboard focus** reliably lands in the terminal, not the sidebar search.
- **Data loss guardrail** — a `BARQ_SUPPORT_DIR` override keeps diagnostics off
  the user's real profiles/vault.

### Added
- **Local-AI setup, built in** — Settings → AI recommends the best Ollama model
  for this Mac (via llm-checker if installed, else a RAM-tiered advisor) and
  installs it with one click + progress.
- **"Connecting…" state**, `ConnectTimeout`, a **Reconnect** button, and the
  failure reason shown when an SSH session can't connect (no more silent blank).
- **Terminal right-click quick actions** — New Tab Here, Save Directory as a
  Host, Copy Working Directory (plus copy/paste/select-all).
- **Quick Connect** (⇧⌘K), **font zoom** (⌘+/⌘−/⌘0), a visible **sidebar toggle**,
  and **drag a tab into the body to open it in its own window**.
- **Release pipeline** — DMG builder, an in-app **update notifier** (polls
  GitHub releases; "Check for Updates…" menu item), and a **Homebrew cask**.

### Changed
- Decluttered the top-right controls into a labeled overflow menu; every icon
  control has a tooltip; single-click (not double) connects a host — the macOS
  idiom. Seamless top bar sits inline with the traffic lights.

## [0.6.0] — 2026-07-08

A reimagined terminal journey — you open Barq to a home, not a blank prompt.

### Added
- **Barq Home** — the app now opens to an intelligent launch surface: a
  time-based greeting, your machines as live cards (kind, tags, AI badge),
  and "jump back in" recents. The lightning wordmark returns you here anytime.
- **Omni-bar** — one input that takes *intent*, not just syntax. It classifies
  what you type and offers ranked actions:
  - a host name → **connect**
  - a command → **run in a new shell**
  - a question ("why is the disk full?") → **ask Barq AI**
  - anything → **search all sessions**
  The classifier is pure and unit-tested (arrow keys + ⏎ to run the top hit).
- **Recents** persist across launches; new users land on Home, returning users
  get their restored sessions.

178 tests across 30 suites.

## [0.5.0] — 2026-07-08

A ground-up visual redesign — seamless, theme-driven, and electric.

### Changed — UI/UX
- **Seamless window.** Hidden title bar with full-size content; a single top bar
  now spans the full width (and is the window-drag region), so the terminal
  reaches every edge. No more stacked title-bar-plus-tab-bar chrome.
- **The whole app adopts the active theme.** New design-token layer derives the
  sidebar, top bar, panels, and surfaces from the terminal theme's own colors
  (elevated/hover/selected/hairline tones) instead of flat gray — it reads as
  one designed object that shifts with the theme.
- **Electric accent.** A signature Barq-lightning accent runs through the
  selected tab, focus ring, AI chip, and primary buttons.
- **Refined top bar + tabs** — soft pills, accent selection, quieter controls.
- **Theme-driven sidebar** with a custom list, hover rows, and an electric AI
  chip; **hard dividers replaced** by tone + subtle hairlines.
- **Polished overlays** — command palette / composer / search now sit on a
  blurred scrim and spring in, with an accent-highlighted selection.
- **New welcome screen** with the lightning mark, tagline, and keycap hints.
- **Motion** on sidebar/AI-panel show-hide and tab changes; terminal panes get a
  subtle inset and an accent focus ring.

## [0.4.1] — 2026-07-08

### Fixed — data loss on upgrade (important)
- **Saved profiles, vault items, and snippets are no longer wiped when a new
  build adds a field.** The models used Swift's synthesized `Codable`, whose
  decoder throws on any key missing from older saved JSON — so each schema
  change (e.g. `agentForward`, `cloudflareAccess`, port-forward filters) caused
  the store to fall back to empty and overwrite the file with defaults. All
  persisted models now decode resiliently: a missing key uses its default
  instead of discarding the record.
- **Stores never overwrite a file they can't parse.** An unreadable
  `profiles.json` / `vault.json` / `snippets.json` is moved aside to
  `<name>.corrupt-<timestamp>` for recovery rather than being replaced, and the
  default profile is only seeded on genuine first launch.

## [0.4.0] — 2026-07-06

SSH connection UX parity + fixes surfaced by real use. 164 tests across 28 suites.

### Fixed
- **Terminal never received keyboard focus** — typing went to the sidebar
  search field. The terminal now actively claims first responder on launch,
  click, tab switch, split, and overlay dismiss (without stealing focus from a
  text field you're deliberately editing).

### Added — SSH auth parity with prateek-term
- **Browse… button** to pick an identity file (opens `~/.ssh`).
- **Paste Private Key** auth mode — key stored in the Keychain, materialized to
  a 0600 temp file at connect for ssh/scp/sftp.
- **Agent forwarding (-A)** toggle and an **Advanced SSH options** editor
  (custom `-o` options).
- **Quick Connect** (⇧⌘K) — connect to an ad-hoc `user@host:port` without
  saving a profile.
- **Font zoom** — Bigger/Smaller/Actual Size (⌘+ / ⌘− / ⌘0), live-applied.

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
