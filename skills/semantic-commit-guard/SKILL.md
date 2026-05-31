---
name: semantic-commit-guard
description: >-
  Review staged changes for meaning before they land, catching leaked secrets,
  architecture or design-pattern violations, risky debug artifacts, large
  accidental files, and docs that drifted from changed behavior. Use when the
  user asks to review staged changes, check whether a commit is safe, guard a
  commit, scan for leaked secrets or policy violations, or install a pre-commit
  hook. Reports BLOCK/WARN findings with staged file:line evidence, fixes, and
  a shareable Rescue Receipt.
---

# Semantic Commit Guard

Lint and `pre-commit` catch formatting and syntax. They can't tell that a diff
hardcoded an API key, smuggled business logic into a controller that's supposed
to stay thin, or shipped a renamed function whose docstring still describes the
old behavior. This skill is that missing judgment layer: it reads the **staged
diff** and blocks the ones that introduce latent debt or risk.

Two modes, same checks:
- **On-demand review** (primary) — you evaluate `git diff --cached` when the
  user asks, before they commit.
- **Installed hook** (optional) — `scripts/install-hook.sh` wires a fast,
  deterministic pre-commit gate (secret + large-file scan) that blocks the
  obvious disasters and reminds the user to run the full semantic review.

## Operating Contract

- Review the staged snapshot, not the working tree. Use `git diff --cached` and
  `git show :path/to/file` when you need full staged file content.
- Block by reporting. Do not edit, unstage, reset, commit, or rotate secrets
  unless the user explicitly asks for that follow-up.
- Never print a complete suspected secret in the response. Show enough context
  to locate it, redact the value, and tell the user to rotate any plausible live
  credential.
- Treat explicit project policy as authoritative. Without policy, report
  architecture concerns as warnings, not blocks.
- Before the final response, leave a Rescue Receipt at
  `.repo-rescue/receipts/<timestamp>-semantic-commit-guard.md` unless the repo is
  read-only or the user asks for no artifacts. The receipt is the only automatic
  file you may create during review, and it must remain uncommitted unless asked.
- For secret false positives, policy severity, staged line mapping, and verdict
  templates, read `references/review-rules.md` only when that detail is needed.

## Battle Card

- **When to use it:** the user asks to review staged changes, check commit
  safety, scan for secrets or policy violations, guard a commit, or install the
  deterministic pre-commit hook.
- **When not to use it:** nothing is staged, the user wants a normal code
  review of unstaged files, the task is to fix findings immediately, or no
  repository policy exists and the concern is only stylistic preference.
- **First command to run:** `git diff --cached --stat` to confirm the staged
  snapshot that will be reviewed.
- **Common failure modes:** reviewing the working tree instead of the index,
  printing a full secret, blocking on undocumented architecture opinions,
  missing staged line numbers, or assuming the hook performs semantic judgment.
- **Good final answer includes:** PASS/BLOCK/WARN verdict, file:line evidence
  with redaction, policy source used, concrete fixes, hook install result when
  relevant, Rescue Receipt path, remaining risk, and recommended next action.

## Workflow

### Step 0 — Confirm there's something to review

- `git diff --cached --stat` — the staged changes. If empty, tell the user
  there's nothing staged and stop (offer to review unstaged `git diff` instead).
- Note the repo root: `git rev-parse --show-toplevel`.

### Step 1 — Load the project's policy

Look for an explicit policy before falling back to defaults. Check, in order:

1. `.semantic-guard.md` at the repo root (project-specific rules — read it and
   treat its rules as authoritative).
2. `AGENTS.md` / `CLAUDE.md` / `CONTRIBUTING.md` — architecture conventions,
   layering rules, "don't do X" notes.
3. Existing lint/security configs when relevant: `.pre-commit-config.yaml`,
   `eslint.config.*`, `pyproject.toml`, `ruff.toml`, `CODEOWNERS`.
4. The default checks below.

If no project policy exists, say which defaults you're applying so the verdict
is transparent.

### Step 2 — Collect staged evidence

```bash
git diff --cached --name-status
git diff --cached --numstat
git diff --cached --check
git diff --cached -U0 --no-ext-diff
```

Use `-U0` to map added lines to exact staged line numbers. For a changed file
that needs more context, inspect the staged blob:

```bash
git show :src/path/to/file.ext
```

Do not judge unstaged edits unless the user explicitly asks for an unstaged
review.

### Step 3 — Run the four checks

Evaluate every added/changed line. For each finding, record
`file:line`, the redacted or minimal offending snippet, the rule it breaks, why
it matters, confidence, and a concrete fix.

| Check | What you're hunting | Severity |
|---|---|---|
| **Secrets / credentials** | Hardcoded API keys, tokens, passwords, private keys, connection strings with embedded creds, `.env` values pasted inline. High-entropy strings assigned to suspicious names (`api_key`, `secret`, `token`, `password`). | **Block** if plausible live secret |
| **Architecture / pattern** | Violations of loaded policy: business logic in the wrong layer, banned import direction, bypassed abstraction, forbidden copy-paste pattern, or TODO/FIXME shipped in place of critical logic. | **Block** for policy violation; **Warn** for heuristic |
| **Docs sync** | A function/flag/endpoint whose signature or behavior changed but its docstring, README, or referenced doc still describes the old behavior. New public API with no doc at all. | **Warn** |
| **Risk smells** | Debug artifacts (`console.log`, `print`, `binding.pry`, `debugger`), commented-out code blocks, disabled tests (`it.skip`, `@pytest.mark.skip`), broad exception swallowing, accidental large files, or secret-adjacent files (`.env`, `*.pem`, `id_rsa`). | **Warn**; **Block** for secrets files |

Guidance:
- **Secrets are the one hard block.** A plausible live credential is never
  acceptable; flag it even if you're unsure, redact it, and tell the user to
  rotate it. A secret in git history isn't removed by unstaging.
- **Architecture findings need the policy.** Without a `.semantic-guard.md` or
  documented convention, downgrade pattern findings to warnings — don't invent
  rules and block on them.
- **Distinguish a test fixture from a real leak.** A key in `tests/fixtures/`
  or an obvious dummy (`sk-test-000...`, `xxxx`) is a warning, not a block.
- **Docs-sync is evidence-based.** Warn when a public name, CLI flag, route,
  schema, or documented behavior changed and nearby docs/comments still say the
  old thing. Do not require docs for every private helper.

### Step 4 — Deliver the verdict

Lead with the decision, then the evidence:

```
GUARD: BLOCKED - 1 blocking issue, 2 warnings

BLOCK  src/config/db.ts:14  [secrets, high confidence]
  Hardcoded DB password in connection string: password=<redacted>
  Fix: move to an env var (process.env.DB_PASSWORD) and rotate the exposed
  credential.

WARN   src/api/users.ts:88  [docs-sync]
  `deleteUser` now soft-deletes, but the docstring still says "permanently
  removes the user". Update the docstring.

WARN   src/api/users.ts:5  [debug-artifact]
  console.log left in a request handler.
```

If clean: `GUARD: PASS - no blocking issues (N files reviewed)` and note any
minor warnings.

After the verdict, create the Rescue Receipt, then stop. Include commands run,
policy/evidence found, staged files reviewed, any files you changed, the risky
staged change or hook install result, remaining risk, and the recommended next
action. Let the user act on it.

## Installing the pre-commit hook (optional)

When the user wants the guard to run automatically, install the deterministic
fast gate. Resolve the script to its absolute path in the installed copy of the
skill (it may live under `skills/`, `.claude/skills/`, `.cursor/skills/`, or
`.codex/skills/`):

```bash
HOOK="$(find "$(git rev-parse --show-toplevel)" -maxdepth 5 \
  -path '*/semantic-commit-guard/scripts/install-hook.sh' 2>/dev/null | head -1)"
bash "$HOOK"            # installs .git/hooks/pre-commit (backs up any existing one)
```

The installed hook runs a **fast, deterministic** secret + large-file + private-key
scan on staged content and exits nonzero (blocking the commit) on a hit — work a
hook can do without an agent. It deliberately does **not** attempt the semantic
architecture/docs judgment; that's your job in the on-demand review above. The
hook prints a reminder to run the full review. Users can bypass it with
`git commit --no-verify` when they've reviewed a finding and accept it.

## Pitfalls

- **A leaked secret isn't fixed by unstaging.** Once it's been written to a
  file the user controls (and especially once committed), it must be rotated.
  Always say so — don't imply `git reset` makes it safe.
- **Don't fabricate architecture rules.** If the repo has no documented
  convention, a "violation" is your opinion — surface it as a warning, not a
  block.
- **False positives on entropy.** UUIDs, git SHAs, content hashes, and test
  fixtures look like secrets. Check the variable name and file location before
  blocking.
- **Review `--cached`, not the working tree.** Judging unstaged edits punishes
  the user for changes they aren't committing.
- **The hook can't think.** The installed hook only catches deterministic
  patterns; it is not a substitute for the on-demand semantic review.
