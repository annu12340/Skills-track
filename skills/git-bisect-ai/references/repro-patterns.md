# Git Bisect Reproduction Patterns

Use this reference when a plain test command is not enough to produce a reliable `git bisect run` oracle.

## Good Reproduction Rules

- Exit 0 only when the bug is absent.
- Exit nonzero when the bug is present.
- Avoid reading mutable local state outside the checkout unless that state is an intentional fixture.
- Keep throwaway scripts outside the bisected worktree and reference them by absolute path.
- Run flaky assertions multiple times inside the script, and fail only on a deterministic signal.

## Worktree Pattern For Dirty Repos

Use a disposable worktree when the main checkout has unrelated user changes:

```bash
WT="${TMPDIR:-/tmp}/git-bisect-ai-$(date +%s)"
git worktree add --detach "$WT" <bad>
cd "$WT"
# validate good/bad bounds and run git bisect here
git bisect reset || true
cd -
git worktree remove "$WT"
```

Do not copy uncommitted app changes into the worktree unless those changes are the reproduction itself. If they are required, create an external repro script or ask before creating a temporary branch.

## Frontend/Browser Oracle

For browser regressions, prefer a one-file Playwright or Puppeteer script in `/tmp`:

```bash
node /tmp/repro-login-button.js
```

The script should:
- Start or connect to the app consistently for each commit.
- Wait for stable UI state, not arbitrary sleeps.
- Assert one observable behavior.
- Exit 1 with a short error message when the behavior is broken.

## Setup Command Patterns

Use `--setup` for work required before each test:
- Dependency install when lockfiles change across the range.
- Build step for generated assets.
- `git submodule update --init --recursive` when submodules are involved.

Use `--build-is-bug` only when setup/build failure is the regression being hunted. Otherwise setup failure should skip that midpoint.

## Rescue Receipt Template

Create this Markdown file under `.repo-rescue/receipts/` before the final
response. Use a UTC timestamp in the filename, for example
`2026-05-31T143012Z-git-bisect-ai.md`.

```markdown
# Rescue Receipt: git-bisect-ai

- Created: <UTC timestamp>
- Repo: <repo root or remote>
- Branch / starting commit: <branch> @ <sha>
- Outcome: <first bad commit found | candidate set | aborted with reason>

## Commands Run
| Command | Purpose | Result |
|---|---|---|
| `<command>` | <why it was run> | <pass/fail/log path> |

## Evidence Found
- Range tested: `<good>..<bad>` (<count> commits, ~<steps> steps).
- Reproduction command: `<test command>`.
- Bisect log: <path or summary>.
- Focused diff evidence: <specific line or behavior from git show output>.

## Files Changed
- <None, or receipt/repro files created. Do not list checked-out historical files as user edits.>

## Culprit Commit
- Commit: `<sha>`
- Author/date/message: <summary>
- Why it broke: <specific logic/API/config change that introduced the failure>

## Remaining Risk
- <flaky oracle, skipped commits, broad reproduction, untested platform, etc.>

## Recommended Next Action
- <revert, targeted fix, regression test, or follow-up owner>
```
