# Semantic Commit Guard Review Rules

Use this reference when deciding whether a staged finding is a block or warning, especially for secrets, staged line mapping, and project policy.

## Secret Classification

Block when both are true:
- The value is credential-shaped: token, private key, connection string with credentials, long API key, cloud secret, signing key, or password.
- The context suggests real use: config, deployment code, app source, CI, infrastructure, or non-test `.env` content.

Warn instead of block when the value is clearly fake:
- Obvious placeholders: `xxxx`, `example`, `dummy`, `test`, `changeme`, `not-a-secret`.
- Test fixtures under `tests/`, `fixtures/`, or docs examples.
- UUIDs, hashes, checksums, lockfile integrity values, or git SHAs without secret-like variable names.

Never print a full suspected secret. Show the file, line, variable name or prefix, and `<redacted>`.

## Architecture Policy

Block architecture findings only when an explicit policy exists:
- `.semantic-guard.md`
- `AGENTS.md`, `CLAUDE.md`, or `CONTRIBUTING.md`
- Lint/security config that clearly encodes the rule

Without policy, phrase the finding as a warning and explain the risk. Do not invent project rules.

## Staged Line Mapping

Use zero-context diffs for precise line numbers:

```bash
git diff --cached -U0 --no-ext-diff
```

When more context is needed, inspect the staged blob rather than the working tree:

```bash
git show :path/to/file
```

## Common Findings

Block:
- Private key material.
- Staged `.env`, `.pem`, `id_rsa`, or similar credential files.
- Real-looking token or password in application/config/deploy code.
- Direct policy violation from `.semantic-guard.md`.

Warn:
- Debug logs in production paths.
- Disabled tests.
- Broad exception swallowing.
- Public API behavior changed without updated docs.
- New public endpoint/CLI flag/config option with no docs.

## Verdict Template

```text
GUARD: BLOCKED - <n> blocking issue(s), <m> warning(s)

BLOCK  <file>:<line>  [<rule>, <confidence>]
  <redacted evidence>
  Fix: <concrete remediation>

WARN   <file>:<line>  [<rule>]
  <evidence>
  Fix: <concrete remediation>
```

## Rescue Receipt Template

Create this Markdown file under `.repo-rescue/receipts/` before the final
response. Use a UTC timestamp in the filename, for example
`2026-05-31T143012Z-semantic-commit-guard.md`.

```markdown
# Rescue Receipt: semantic-commit-guard

- Created: <UTC timestamp>
- Repo: <repo root or remote>
- Branch / commit reviewed: <branch> @ <sha>
- Outcome: <PASS | BLOCKED | WARNINGS ONLY | HOOK INSTALLED>

## Commands Run
| Command | Purpose | Result |
|---|---|---|
| `<command>` | <why it was run> | <pass/fail/summary> |

## Evidence Found
- Policy sources: <.semantic-guard.md, AGENTS.md, defaults, etc.>
- Staged files reviewed: <count and names>
- Findings: <BLOCK/WARN/PASS with redacted evidence and file:line>

## Files Changed
- <Usually only this receipt. For hook installation, include `.git/hooks/pre-commit` and backup path.>

## Culprit / Root Cause
- <Risky staged change, leaked secret location, policy violation, or "None found".>

## Remaining Risk
- <Unstaged files not reviewed, generated files skipped, secrets requiring rotation, hook limits, etc.>

## Recommended Next Action
- <Fix finding, rotate secret, update docs, install hook, or proceed with commit>
```
