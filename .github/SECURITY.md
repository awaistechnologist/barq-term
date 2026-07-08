# Security Policy

Barq is an SSH/serial/telnet client, a secret store (the Context Vault), and an
MCP server that lets AI agents drive sessions. Security is a first-class concern.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's
**private vulnerability reporting** for this repo (the Security tab →
"Report a vulnerability"), including:

- a description of the issue and its impact,
- steps to reproduce or a proof of concept,
- the affected version (shown on the Barq Home screen).

You'll get an acknowledgement within a few days. Please give a reasonable
window to ship a fix before public disclosure.

## Security model

Barq's design rests on a few guarantees. If you find a way to break any of
these, that's a vulnerability worth reporting:

- **Agent access is opt-in per profile.** An MCP agent can only open a session
  for a profile whose **AI** chip the user has enabled. Agent-created profiles
  start with AI access **off**.
- **The Context Vault's `secret` policy.** A `secret` value may be *used* inside
  a command via `${BARQ:NAME}` (Barq substitutes it before sending) but is
  **never returned** to an agent — not through `vault_get`, and not echoed back
  through `run_command`/`read_output` (expanded secrets are redacted from any
  output returned over the bridge).
- **Dangerous-command guardrails.** When enabled, destructive commands
  (`rm -rf`, `mkfs`, force-push, DB drops, pipe-to-shell, power changes, …)
  require a native approval prompt before an agent can run them. The classifier
  runs against the **expanded** command, so payloads hidden in vault variables
  are still caught.
- **Local-only IPC.** The app↔`barq-mcp` bridge is a Unix domain socket
  restricted to the current user (`getpeereid` same-uid check, `0600` socket in
  a `0700` directory).
- **Secrets at rest.** Passwords, vault values, and API keys live in the macOS
  Keychain (`WhenUnlockedThisDeviceOnly`), never in plaintext on disk.
- **Deep links are confirmed.** `barq://` links never auto-connect; the user is
  prompted before any action.

## Scope notes

- Barq launches the system `ssh`/`scp`/`sftp` via `argv` (never a shell string),
  so there is no local shell-injection surface from profile fields. The remote
  shell, of course, runs whatever a session sends it — that is the nature of a
  terminal.
- The app is currently **ad-hoc signed**. Developer ID signing + notarization is
  on the roadmap.
