# Barq — development conventions

Barq is a native Swift/SwiftUI macOS terminal (SwiftTerm-based) with SSH/serial/telnet sessions, a Context Vault, an MCP server (`barq-mcp`), and local-first AI (Ollama, optional OpenRouter).

## TDD is the workflow here

- Every behavior change starts with (or immediately gains) a test. No feature lands without coverage of its logic layer.
- Run the suite with `scripts/test.sh` (wires up Testing.framework paths for Command Line Tools installs; extra args pass through, e.g. `scripts/test.sh --filter VaultStoreTests`).
- Tests use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — not XCTest (not available with CLT-only installs).
- Keep pure logic out of views so it stays testable: command building in `SSHCommandBuilder`, marker detection in `CommandMarker`, telnet negotiation in `TelnetBackend.parseTelnet`, policy enforcement in `VaultStore`/`BridgeHandler`.
- Vault tests write real Keychain entries — always use unique `TEST_*` names and `defer { vault.remove(name:) }` cleanup.
- Stores take a `fileURL` parameter — always point tests at a temp file, never at real app data.

## Build & run

- `swift build` — builds the app and `barq-mcp`.
- `swift run Barq` — run the app from the CLI.
- `scripts/make-app.sh` — produce a distributable `Barq.app` in `dist/`.

## Architecture notes

- `BridgeHandler` is the single MCP enforcement point: per-profile `aiAllowed` and per-variable vault policies (`open`/`approval`/`secret`) are checked there.
- Secrets rule: a `secret` vault value may be *expanded* into commands (`${BARQ:NAME}`) but never *returned* to an agent.
- All secrets (passwords, vault values, API keys) live in the macOS Keychain — never in JSON on disk.
- UI state lives in `AppState.shared` (@MainActor); sessions in `SessionManager.shared`.
