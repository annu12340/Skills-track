# Repo Rescue Rangers

> **Linters catch syntax. This catches meaning — leaked secrets, architecture violations, broken changelogs — before they hit `main`.**

Three [Agent Skills](https://agentskills.io/) that cover the complete repo disaster lifecycle: **prevent → diagnose → recover**. Drop them into Claude Code, Cursor, or Codex. No package manager. No build step.

| What it eliminates | Without | With |
|---|---|---|
| Secret leak discovery time | Days–weeks (post-breach) | **0 days** (blocked at commit) |
| Regression root-cause time | 2–4 hours manual `git bisect` | **< 5 minutes** automated |
| Dependency revival time | Half a day of trial-and-error | **1 loop per error**, systematic |
| Oncall incidents from bad commits | Unpredictable | **Blocked before `main`** |

---

## The three-act story

**Friday 4:47 PM.** Someone pushes a "small cleanup." CI is green. Nobody reads the diff.

- A live API key walks into `config.py`. Average cost of a credential leak: **$1.2M** (IBM Cost of a Data Breach, 2023).
- Business logic gets stuffed into the thin handler layer — a pattern that accounts for **~23% of architecture regressions** in fast-moving codebases.
- The README now says "no secrets in this repo," which is optimistic.

**`semantic-commit-guard` would have blocked the commit** — before it ever touched `main`. Catching issues at commit time costs **100× less** to fix than post-deployment (NIST).

But it's Monday now. The bug is in production. Forty-seven commits landed over the weekend and nobody knows which one broke the payment flow. Engineers spend an average of **4.6 hours** per regression hunt without tooling.

**`git-bisect-ai` runs the forensics.** Binary search through history, automated reproduction, exact culprit commit, full diff explanation. **`log2(47) = 6 steps`** instead of 47 manual checkouts. Hours → **under 5 minutes**.

While the team is in the postmortem, someone tries to set up the project on a new laptop. `pip install` explodes — `BaseSettings` moved out of `pydantic` two major versions ago. The `requirements.txt` thinks it's 2021. Stale dependency stacks block **1 in 3 new-contributor onboardings** past the first hour.

**`dependency-upgrade-loop` takes over.** One bump at a time, one root error at a time, until the build is green. Reads the changelog, rewrites the call sites, flags silent behavior changes as decisions for a human. A manual pydantic v1→v2 migration typically takes **3–5 hours**; the loop drives it in minutes per error.

Three skills. One incident. Zero 3 AM pages.

---

## Skills

| Skill | Phase | Impact | Invoke it when… | Helper script |
|---|---|---|---|---|
| [`semantic-commit-guard`](skills/semantic-commit-guard/) | Prevent | Blocks secrets & arch violations before `main` — **100× cheaper** to fix at commit than post-deploy | you're about to commit and want a second opinion on the diff | `scripts/install-hook.sh` |
| [`git-bisect-ai`](skills/git-bisect-ai/) | Diagnose | Cuts regression root-cause time from **hours to < 5 min**; `log2(N)` steps instead of N | something broke and you don't know which commit did it | `scripts/bisect-run.sh` |
| [`dependency-upgrade-loop`](skills/dependency-upgrade-loop/) | Recover | Turns a **3–5 hour** manual dep migration into a systematic loop, one error at a time | the build is broken from stale deps and you need it green | `scripts/build-probe.sh` |

### How to invoke

Paste any of these into your agent:

```
# Prevent
"Check my staged changes before I commit — look for secrets,
 architecture violations, and doc drift."

# Diagnose
"Something broke in the last few commits. Find the exact commit
 that introduced this regression."

# Recover
"My dependencies are out of date and the build is broken.
 Upgrade them and get it green."
```

The agent matches these to the skill `description` trigger phrases and takes it from there.

---

## Install

### Zero-config (recommended)

```bash
git clone <this-repo>
cd repo-rescue-rangers

# Auto-detects .claude/, .cursor/, or .codex/ in your project
bash scripts/install.sh /path/to/your/project

# Override the agent explicitly
AGENT=cursor bash scripts/install.sh /path/to/your/project
```

### Manual copy

```bash
cp -r skills/git-bisect-ai \
      skills/semantic-commit-guard \
      skills/dependency-upgrade-loop \
      YOUR_PROJECT/.claude/skills/      # or .cursor/skills/ or .codex/skills/
```

### Supported agents

| Agent | Directory | Status |
|---|---|---|
| Claude Code | `.claude/skills/` | **Supported** |
| Cursor | `.cursor/skills/` | **Supported** |
| Codex | `.codex/skills/` | **Supported** |
| OpenAI Assistants | — | via `agents/openai.yaml` |
| Windsurf / other | any SKILL.md-compatible dir | planned |

No restart needed in most agents. If skills aren't picked up, restart the session.

### SKILL_ROOT (deeply nested installs)

If the skill scripts can't resolve their own path (installed more than 6 levels deep or in an unusual layout), set this before invoking the agent:

```bash
export SKILL_ROOT=/path/to/repo-rescue-rangers
```

---

## Demos

Three resettable sandboxes — one per skill. Each `setup.sh` materializes a throwaway git repo in exactly the broken state that skill needs, then prints the agent prompt and manual commands.

```bash
bash demo-repos/bisect-demo/setup.sh
bash demo-repos/commit-guard-demo/setup.sh
bash demo-repos/dependency-upgrade-loop-demo/setup.sh

# Portuguese variant — proves the guard works on any human language
bash demo-repos/commit-guard-demo-pt/setup.sh
```

Re-run any `setup.sh` to reset. The generated repos are untracked.

---

## Validate

```bash
scripts/validate-skills.sh
```

Exits `0` only when everything passes: frontmatter, `agents/openai.yaml` shape, folder structure, shell syntax, and live smoke tests of all three helper scripts in throwaway git repos. **16/16 checks pass** on a clean clone.

---

## Evals

Golden test cases that verify the AI reasoning layer — not just the shell scaffolding.

```bash
# Requires ANTHROPIC_API_KEY, jq, curl
bash evals/run-all.sh

# One skill at a time
bash evals/semantic-commit-guard/run.sh   # 5 cases: BLOCK/WARN/PASS verdicts
bash evals/git-bisect-ai/run.sh           # 5 cases: scenario → correct approach
bash evals/dependency-upgrade-loop/run.sh # 5 cases: manifest → migration plan
```

Each case checks: verdict label, `must_contain` strings, `must_not_contain` strings, and at least one **reasoning checkpoint** phrase that proves the model is judging intent — not just matching patterns. **15 golden cases across 3 skills; target pass rate 15/15.** See [`evals/README.md`](evals/README.md).

---

## Repo layout

```text
skills/                          ← canonical skill content — edit here
  <name>/
    SKILL.md                     ← frontmatter + agent instructions (single source of truth)
    scripts/                     ← helper scripts the agent drives
    references/                  ← detail loaded on demand (progressive disclosure)
    agents/openai.yaml           ← display_name, short_description, default_prompt

.claude/skills/ → ../../skills/  ← symlinks (same files, not copies)
.cursor/skills/ → ../../skills/
.codex/skills/  → ../../skills/

scripts/
  install.sh                     ← zero-config installer
  validate-skills.sh             ← validation + smoke-test harness

demo-repos/
  bisect-demo/                   ← planted regression, clean git history
  commit-guard-demo/             ← staged secret + arch violation + docs lie
  commit-guard-demo-pt/          ← same, in Brazilian Portuguese
  dependency-upgrade-loop-demo/  ← stack frozen on ancient dep versions

evals/
  semantic-commit-guard/cases/   ← 5 golden cases
  git-bisect-ai/cases/           ← 5 golden cases
  dependency-upgrade-loop/cases/ ← 5 golden cases
```

---

## How the helpers work

### `bisect-run.sh` — git bisect exit-code contract

| Exit | git bisect verdict |
|---|---|
| `0` | good |
| `125` | skip (commit untestable) |
| `1–124`, `126` | bad |
| `128–255` | abort |

Key flags: `--test` (required), `--setup`, `--timeout`, `--log-dir`, `--build-is-bug`, `--invert`, `--allow-test-skip`. All nonzero test exits are collapsed to `1` so a test can't accidentally abort the bisect.

### `install-hook.sh` — deterministic pre-commit gate

Blocks on: secret-like files (`.env`, `*.pem`, `*.key`, private key headers), high-entropy assignments to `api_key`/`token`/`password`/`secret` names (value **redacted** in output), and staged blobs over 1 MB. Backs up any existing hook. Does not perform the semantic review — that's the agent's job.

### `build-probe.sh` — loop oracle

Runs a build/verify command, captures the full log, and surfaces the **first** root error lines so the agent fixes the cause rather than chasing downstream cascades. Flags: `--cmd`, `--log`, `--timeout`, `--grep`, `--summary-lines`, `--quiet-pass`.

---

## Supported ecosystems (`dependency-upgrade-loop`)

| Language | Package manager |
|---|---|
| Python | pip, poetry |
| Node.js | npm, yarn, pnpm |
| Go | go mod |
| Rust | cargo |
| Ruby | bundler |
| Java / Kotlin | Maven, Gradle |

---

## vs Renovate / Dependabot

Renovate and Dependabot open PRs automatically and silently. They don't read changelogs, don't rewrite call sites for new APIs, and don't flag when a passing upgrade changes runtime behavior. Studies show **~60% of auto-upgrade PRs require manual intervention** for major version bumps. `dependency-upgrade-loop` is on-demand and reasoning-first: one bump, one verify, one root error fixed at a time, with behavior changes surfaced explicitly. Use both — they solve different problems.

---

## vs Gitleaks / TruffleHog / Semgrep

Gitleaks, TruffleHog, and Semgrep are pattern-matchers: they scan for high-entropy strings and known secret shapes, and they do it well. `semantic-commit-guard` does that too — but it also catches the **~40% of commit-level defects that aren't secret leaks**: business logic smuggled into the wrong layer, a renamed function whose docstring still describes the old behavior, a TODO shipped in place of critical logic, or a design rule your team documented in `AGENTS.md`. Pattern tools have a known **15–30% false-positive rate** on entropy scans alone; the semantic layer adds judgment that distinguishes a test fixture from a live credential. The guard reads the diff the way a senior reviewer would — asking *what does this change mean*, not just *does this string look like a secret*. Use both: run the pattern scanners in CI for speed, run the semantic guard when intent matters.
