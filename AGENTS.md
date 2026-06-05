# AGENTS.md

Orientation for an agent **evaluating** this repository. Read this first, then
`README.md` for the human-facing summary and `CLAUDE.md` for authoring rules.

## What this repo is (and isn't)

A collection of three portable **Agent Skills** — the "Repo Rescue Rangers" —
that cover the repo lifecycle: **prevent → diagnose → recover**. The deliverable
is the *skill definitions themselves* (instructions + bundled helper scripts),
plus a marketing landing page and demo fixtures.

There is **no application to build, no package manager, and no dependency install
step.** Do not look for a `package.json` to `npm install`, a server to boot, or a
test framework to run. "Does it work?" is answered by `scripts/validate-skills.sh`
and by exercising the demos. Evaluate the skills as *documents + small shell
tools*, not as an app.

| Skill (folder = `name`) | Phase | One-line purpose | Bundled helper |
|---|---|---|---|
| `git-bisect-ai` | diagnose | Find the first commit that introduced a regression via `git bisect run` | `scripts/bisect-run.sh` |
| `semantic-commit-guard` | prevent | Review staged diffs for *meaning*; install a deterministic pre-commit gate | `scripts/install-hook.sh` |
| `dependency-upgrade-loop` | recover | Upgrade stale deps and rewrite breaking code until the build is green | `scripts/build-probe.sh` |

## Repository map

```text
skills/                     ← CANONICAL skill content. Evaluate THIS tree.
  <skill>/
    SKILL.md                ← frontmatter (name, description) + agent instructions
    scripts/                ← executable helpers the skill drives
    references/             ← deeper guidance the skill loads on demand
    agents/openai.yaml      ← Codex/OpenAI interface metadata
.claude/skills/  → ../../skills/<skill>   (symlinks)
.cursor/skills/  → ../../skills/<skill>   (symlinks)
.codex/skills/   → ../../skills/<skill>   (symlinks)
scripts/validate-skills.sh  ← authoritative validation + smoke-test harness
demo-repos/<demo>/setup.sh  ← materialize a throwaway repo per skill
docs/                       ← supporting docs (e.g. the upgrade-loop workflow DAG)
README.md                   ← human overview / install instructions
CLAUDE.md                   ← authoring conventions for skill content
webpage/index.html          ← hand-maintained marketing page
```

**Critical for evaluation:** `.claude/`, `.cursor/`, and `.codex/` skill folders
are **symlinks into `skills/`** — the same files, not three separate
implementations. Count and review each skill **once**. Edit/assess only `skills/`.

## How to evaluate (recommended order)

1. **Run the validation harness — this is the source of truth for "it works":**
   ```bash
   scripts/validate-skills.sh
   ```
   Expect every line `[PASS] …` and a final `[PASS] all skill validations passed`
   (exit 0). It checks, per skill: valid frontmatter (hyphen-case `name`,
   present `description`, body ≤ 500 lines), `agents/openai.yaml` shape, allowed
   folder layout, `bash -n` syntax on every `*.sh`, and **functional smoke tests**
   of all three helper scripts in disposable git repos. A nonzero exit or any
   `[FAIL]` is a real defect.

2. **Read each `SKILL.md`.** Judge it as an instruction set for an autonomous
   agent: Is the `description` trigger-focused ("Use when …" with concrete
   phrases)? Is there a safety step, a clear workflow, checkpoints with the user,
   and a pitfalls section? Is the helper script's contract documented?

3. **Exercise a demo end-to-end** (optional but high-signal):
   ```bash
   cd demo-repos/bisect-demo && bash setup.sh   # prints the exact prompt to use
   ```
   Each `setup.sh` materializes a throwaway git repo with the contradictory
   starting state that skill needs, and prints the prompt + manual commands.
   Re-running resets it. (These generated repos are untracked — not part of the
   deliverable.)

4. **Spot-check the helper contracts** (see next section) if you want to verify
   behavior beyond the smoke tests.

## Helper-script contracts (what correctness means)

These are the load-bearing pieces. The smoke tests in `validate-skills.sh` cover
each; here is what they must satisfy.

### `git-bisect-ai/scripts/bisect-run.sh`
Wrapper handed to `git bisect run`. **Exit codes are git bisect's verdict, not
normal shell semantics:** `0`=good, `125`=skip (untestable commit),
`1`–`124`/`126`=bad, `128`–`255`=abort. Flags: `--test "<cmd>"` (required),
`--setup`, `--timeout`, `--setup-timeout`, `--log-dir`, `--build-is-bug`
(failing setup ⇒ bad, for hunting broken builds), `--invert` (a *passing* test is
bad), `--allow-test-skip` (preserve a test exit `125` as skip). It collapses
other nonzero test exits to a plain `1` so a test can't accidentally abort the
search.

### `semantic-commit-guard/scripts/install-hook.sh`
Installs a **fast, deterministic** pre-commit gate (leaked-secret patterns,
secret-like files such as `.env`/`*.pem`, private-key headers, oversized blobs),
backing up any existing hook to `pre-commit.backup`. It **redacts** matched
secret values in its output (must never echo the secret). It blocks with exit `1`
and is bypassable with `git commit --no-verify`. By design it does **not** attempt
architecture/docs judgment — that deeper "semantic" review is the *agent's* job,
performed on demand per the SKILL.md. Don't penalize the script for not doing the
LLM-level review; check that the SKILL.md describes it.

### `dependency-upgrade-loop/scripts/build-probe.sh`
Runs a build/verify command as the loop's pass/fail oracle and surfaces the
*first root error* (not the cascade). Flags: `--cmd` (required), `--log`,
`--timeout`, `--grep`, `--summary-lines`, `--quiet-pass`. Exit: `0` pass, `1`
fail (prints highlighted error lines + log path), `124` timeout, `2` usage error.

## Conventions an evaluator should hold the skills to

- **Skill = one folder under `skills/`** containing `SKILL.md` and optionally
  `scripts/`, `references/`, `agents/`, `assets/`. No other top-level artifacts
  (the harness enforces this).
- **Frontmatter:** `name` is hyphen-case, ≤ 64 chars, no leading/trailing/double
  hyphens, and should match the folder name. `description` is present and written
  as triggers ("Use when the user …").
- **SKILL.md is the single source of truth** for behavior; the landing page is
  separate marketing copy that must be updated by hand if a name/path changes.
- **Body length:** `SKILL.md` body ≤ 500 lines.
- **`agents/openai.yaml`:** has an `interface:` block with `display_name`,
  `short_description`, and a `default_prompt` that references `$<skill-name>`.

## Known scope boundaries (don't flag these as bugs)

- The mirror dirs (`.claude`/`.cursor`/`.codex`) are intentional symlinks, not
  duplicated work.
- The semantic guard's *deep* review (architecture/design-pattern/docs-sync) is
  an agent task invoked via the SKILL.md, not something the installed shell hook
  performs. The hook is only the deterministic fast gate.
- Demo `setup.sh` scripts generate **untracked** throwaway git repos on disk;
  only the `setup.sh` files are tracked.
- There may be a stray untracked `skills-landing copy.html` — a scratch copy, not
  a deliverable; ignore it.

## Command cheat-sheet

```bash
scripts/validate-skills.sh                     # validate + smoke-test everything (must exit 0)
ls skills/                                      # the three canonical skills
sed -n '1,12p' skills/*/SKILL.md                # read each skill's frontmatter
cd demo-repos/dependency-upgrade-loop-demo && bash setup.sh   # try a demo
git status                                      # rename/edit state is unstaged unless asked
```
