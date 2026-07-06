# Contributing to Barq

Thanks for your interest in Barq — a native Swift macOS terminal with SSH,
serial, telnet, a Context Vault, and an MCP server for AI agents.

## Getting set up

Requirements: macOS 13+ and a Swift 6 toolchain (Command Line Tools are enough —
no Xcode needed).

```bash
git clone <your-fork> && cd barq
swift build            # builds the app and barq-mcp
swift run Barq         # run the app
./scripts/make-app.sh  # produce dist/Barq.app
```

## TDD is the house style

Every behavior change starts with (or immediately gains) a test. No feature
lands without coverage of its logic layer.

```bash
./scripts/test.sh                      # full suite (127 tests / 21 suites)
./scripts/test.sh --filter VaultStore  # one suite
```

- Tests use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`),
  not XCTest (XCTest isn't available on Command Line Tools-only installs).
- Keep pure logic out of views so it stays testable: command building in
  `SSHCommandBuilder`, marker detection in `CommandMarker`, telnet negotiation
  in `TelnetBackend.parseTelnet`, policy enforcement in `VaultStore` /
  `BridgeHandler`, command classification in `CommandGuard`.
- Stores take a `fileURL` parameter — always point tests at a temp file, never
  at real app data. Vault tests write real Keychain entries: use unique `TEST_*`
  names and `defer { vault.remove(name:) }` cleanup.

## Security-sensitive areas

Barq is an SSH client and secret store. Changes to any of these need extra care
and a test that pins the guarantee (see `.github/SECURITY.md`):

- `BridgeHandler` — the single MCP enforcement point (per-profile AI access,
  vault policy, guardrails). Vault expansion and guardrail classification order
  matters: **expand, then classify, then run**.
- `VaultStore` — the `open`/`approval`/`secret` policy and secret redaction.
- `SSHCommandBuilder` — argv construction; hosts are validated and `--` guards
  the destination to prevent option injection.
- `Keychain` — all secrets at rest.

## Commit style

Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`). Keep the
suite green and lint clean before opening a PR.
