# Repo Rescue Rangers

### What it is

Three portable Agent Skills covering the repo lifecycle — **prevent** (`semantic-commit-guard`),
**diagnose** (`git-bisect-ai`), **recover** (`dependency-upgrade-loop`) — each with a `SKILL.md`, a
working helper script, a reference doc, and OpenAI agent metadata. Canonical content lives in
`skills/`; `.claude/`, `.cursor/`, `.codex/` are symlinks into it. A validation harness, three
resettable demo repos, a landing page, and a workflow diagram round it out.

### Verdict: strong hackathon project — genuinely shippable, not a mockup

Verified rather than trusted:

- **`scripts/validate-skills.sh` exits 0** — metadata, folder shape, shell syntax, and live smoke
  tests of all three helpers in throwaway git repos all pass.
- **The scripts are real, not props.** `bisect-run.sh` correctly maps to git bisect's exit-code
  contract (0/125/bad/abort), collapses stray nonzero codes so the test can't accidentally abort the
  search, handles `timeout`/`gtimeout` absence gracefully, and writes per-commit JSON forensics.

Three [Agent Skills](https://agentskills.io/) that cover the repo lifecycle — **prevent**, **diagnose**, **recover**.

| Skill | Role | Status |
|---|---|---|
| [git-bisect-ai](skills/git-bisect-ai/) | Find the exact commit that introduced a regression | Implemented (+ `scripts/bisect-run.sh`) |
| [semantic-commit-guard](skills/semantic-commit-guard/) | Review staged diffs and install a deterministic pre-commit fast gate | Implemented (+ `scripts/install-hook.sh`) |
| [dependency-upgrade-loop](skills/dependency-upgrade-loop/) | Upgrade stale deps and rewrite code until the build passes | Implemented (+ `scripts/build-probe.sh`) |

See [skills-landing.html](skills-landing.html) for the full marketing page and demo scenarios.

## Layout

Canonical skill content lives in `skills/`. IDE-specific directories are symlinks:

```text
skills/                          ← edit skills here
.claude/skills/  → ../../skills/
.cursor/skills/  → ../../skills/
.codex/skills/   → ../../skills/
```

## Install in your project

Copy the skill folders from `skills/` into your agent's skills directory:

| Agent | Destination |
|---|---|
| Claude Code | `YOUR_PROJECT/.claude/skills/` |
| Cursor | `YOUR_PROJECT/.cursor/skills/` |
| Codex | `YOUR_PROJECT/.codex/skills/` |

```bash
# Example: install all three for Cursor
mkdir -p YOUR_PROJECT/.cursor/skills
cp -r skills/git-bisect-ai skills/semantic-commit-guard skills/dependency-upgrade-loop \
  YOUR_PROJECT/.cursor/skills/
```

No package manager or build step required. Restart the agent session if skills are not picked up automatically.

## Try the demos

Each demo under `demo-repos/` has a `setup.sh` that materializes a throwaway git repo for one skill.
Run a setup script, then follow the prompt it prints:

```bash
cd demo-repos/bisect-demo
bash setup.sh
```

Re-run that demo's `setup.sh` to reset it.

## Validate the skills

Run the repo-level validation harness before publishing or copying the skills:

```bash
scripts/validate-skills.sh
```

It validates skill metadata, shell syntax, installable skill folder shape, and smoke tests the bundled helpers in temporary git repos.

## Technical details

### Repository architecture

Canonical skill content lives once, under `skills/<name>/`. The agent-specific
directories (`.claude/skills/`, `.cursor/skills/`, `.codex/skills/`) are **symlinks**
into that tree, so every tool sees identical content and there is no copy to keep in
sync. Each skill's folder name matches its frontmatter `name:` (e.g.
`skills/semantic-commit-guard/` → `name: semantic-commit-guard`), which is also the
invocation token (`/semantic-commit-guard`) and the `$name` used in `agents/openai.yaml`.

Each skill folder follows a fixed shape:

```text
skills/<name>/
├── SKILL.md          # frontmatter (name, description) + the skill's instructions
├── scripts/          # executable helpers the skill drives
├── references/       # detail loaded only when needed (progressive disclosure)
└── agents/openai.yaml  # UI metadata; default_prompt must mention $<name>
```

`SKILL.md` is the single source of truth for behavior. Helpers resolve their own path
at runtime via `find "$(git rev-parse --show-toplevel)" -path '*/<name>/scripts/...'`,
so a skill works regardless of which agent directory it was installed under.

### `git-bisect-ai` — `scripts/bisect-run.sh`

The wrapper handed to `git bisect run`. Its exit code **is** git bisect's verdict, not
normal shell semantics:

| Exit code | Meaning to git bisect |
|---|---|
| `0` | good (test passed) |
| `125` | skip (commit can't be tested, e.g. won't build) |
| `1`–`124`, `126` | bad (test failed) |
| `128`–`255` | abort the entire bisect |

| Flag | Effect |
|---|---|
| `--test "<cmd>"` | **Required.** Command whose exit code defines good/bad. |
| `--setup "<cmd>"` | Run before the test (install deps, compile). |
| `--timeout <s>` | Kill the test after N seconds; a hang counts as bad. |
| `--setup-timeout <s>` | Separate limit for the setup step. |
| `--log-dir <path>` | Save per-commit `setup`/`test` logs and a JSON summary. |
| `--build-is-bug` | A failing setup means **bad**, not skip — for hunting broken builds. |
| `--invert` | A *passing* test is bad — finds when a failing test started passing. |
| `--allow-test-skip` | Preserve a test exit `125` as skip rather than collapsing it. |

Key safety behavior: any nonzero test exit (including `124` timeout, `125`, `128`) is
**collapsed to plain `1` (bad)** unless `--allow-test-skip` is set, so the test command
can never accidentally abort the search. Timeouts use `timeout`/`gtimeout` if present and
degrade to running untimed (with a warning) otherwise.

### `semantic-commit-guard` — `scripts/install-hook.sh`

Installs a fast, deterministic `pre-commit` hook into `.git/hooks/`. An existing hook is
backed up to `pre-commit.backup` (then `.backup.1`, `.backup.2`, …) before replacement;
re-running is idempotent. The hook scans **staged content only** (`--cached`,
`--diff-filter=ACMR`, NUL-safe) and blocks the commit (exit 1) on:

1. **Secret-like files** — `.env`, `*.pem`, `*.key`, `*id_rsa`/`id_dsa`/`id_ecdsa`/`id_ed25519`.
2. **Secret-like added lines** — key/secret/password/token assignments of a 16+ char
   high-entropy value, or a `-----BEGIN … PRIVATE KEY-----` header. The offending value is
   **redacted** in output; only `file:line` is shown.
3. **Oversized blobs** — staged objects larger than 1 MB.

It deliberately does **not** attempt the semantic architecture/docs review — that is the
agent's on-demand job. The hook prints a reminder, and a reviewed finding can be overridden
with `git commit --no-verify`.

### `dependency-upgrade-loop` — `scripts/build-probe.sh`

Runs a build/verify command, captures the full log, and surfaces the **first** root error
so the agent fixes the cause rather than chasing downstream cascades.

| Exit code | Meaning |
|---|---|
| `0` | build/verify succeeded |
| `1` | failed (highlighted root error + log path printed) |
| `124` | timed out |
| `2` | usage error |

| Flag | Effect |
|---|---|
| `--cmd "<cmd>"` | **Required.** Build/test/typecheck command; exit 0 = healthy. |
| `--log <path>` | Where to write the full output (default `$TMPDIR/build-probe.log`). |
| `--timeout <s>` | Kill after N seconds; a hang is a failure. |
| `--grep "<regex>"` | Extra error pattern to highlight on top of built-ins. |
| `--summary-lines <n>` | How many matching error lines to print (default 15). |
| `--quiet-pass` | On success, save the log without echoing it. |

On failure it greps the saved log for a built-in error vocabulary (`error`, `cannot find`,
`no module named`, `unresolved`, `peer dep`, `ImportError`, …) and prints the first matching
lines, which is where the root cause usually lives.

### Validation harness — `scripts/validate-skills.sh`

The source of truth for "does it work?" Exits `0` only when every check passes:

- **Metadata** — frontmatter `name` is hyphen-case, ≤64 chars, no leading/trailing/double
  hyphens; `description` present; SKILL.md body ≤500 lines.
- **`agents/openai.yaml` shape** — has `interface`, `display_name`, `short_description`, and a
  `default_prompt` mentioning the exact `$<name>`.
- **Folder shape** — only `SKILL.md`, `scripts/`, `references/`, `agents/`, `assets/` allowed.
- **Shell syntax** — `bash -n` on every `*.sh` (skills, scripts, and demo setups).
- **Smoke tests** — each helper is exercised in a throwaway git repo: a planted regression for
  `bisect-run`, a leaked-secret diff for the hook, and a failing build for `build-probe`.

### Strengths

1. **The skill writing is excellent and consistent.** Every `SKILL.md` follows the same template —
   Operating Contract → Battle Card → numbered Workflow → Pitfalls → Rescue Receipt — and the
   `description` fields are written as real trigger phrases ("used to work," "stopped working"). The
   progressive-disclosure split (lean SKILL.md, detail pushed to `references/`) matches Agent Skills
   best practice.
2. **Hard-won correctness in the details.** Bisect runner exit-code semantics; the guard reviewing
   `--cached` not the working tree and refusing to print full secrets; the upgrade loop's "one
   logical change per verify run" and "fix the *first* root error, not the cascade."
3. **Portability is real**, via the symlink-into-`skills/` design, and the runtime `find` for the
   script path means it works regardless of which agent dir it's installed under.
4. **Demos are well-designed** — each `setup.sh` plants a scenario that *only* that skill resolves,
   and they're deliberately kept separate.


### Bottom line

Well above typical hackathon quality: the skills are correct, validated, documented, and portable,
with helper scripts that show real engineering judgment.