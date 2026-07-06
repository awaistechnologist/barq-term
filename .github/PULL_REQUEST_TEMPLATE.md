## What & why

<!-- What does this change do, and why? -->

## Testing

<!-- How did you verify it? New/changed tests? -->

- [ ] `./scripts/test.sh` passes (127+ tests)
- [ ] `swift build` clean
- [ ] Added/updated tests for the logic changed

## Security checklist (if touching sessions, vault, MCP, or Keychain)

- [ ] No new path returns a `secret` vault value to an agent
- [ ] Guardrail classification still runs on the **expanded** command
- [ ] `argv` construction unchanged or still `--`-guarded (no option injection)
- [ ] Secrets stay in the Keychain, never written to disk/logs
