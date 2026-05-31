# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of **Agent Skills** (the "Repo Rescue Rangers") — portable skill
folders that work in Claude Code, Cursor, Codex, and other Agent Skills–compatible
tools. Canonical content lives in `skills/`; `.claude/skills/`, `.cursor/skills/`,
and `.codex/skills/` are symlinks into that tree.

There is no application to build, no package manager, and no dependency install
step. The deliverables are the skill definitions themselves plus a marketing
landing page (`skills-landing.html`).

The three skills cover the repo lifecycle — prevent, diagnose, recover:

| Skill folder | Purpose | Status |
|---|---|---|
| `skills/git-bisect-ai/` | Automate `git bisect run` to find the commit that introduced a regression | **Implemented** (SKILL.md + working `scripts/bisect-run.sh`) |
| `skills/semantic-commit-guard/` | Pre-commit gate that judges the *meaning* of staged changes | **Implemented** (SKILL.md + `scripts/install-hook.sh`) |
| `skills/dependency-upgrade-loop/` | Iteratively upgrade dependencies and rewrite code until the build passes | **Implemented** (SKILL.md + `scripts/build-probe.sh`) |

Each skill's folder name matches its frontmatter `name:` (e.g. `skills/semantic-commit-guard/`
defines `name: semantic-commit-guard`); keep them in sync when adding or renaming a skill.

## Skill structure conventions

Each skill is a folder under `skills/` containing:
- A `SKILL.md` with YAML frontmatter (`name`, `description`) followed by the skill's instructions.
  The `description` is the trigger text the agent uses to decide when to invoke the skill — write it
  as "Use when the user…" with concrete trigger phrases.
- An optional `scripts/` directory for executable helpers the skill drives.
- An optional `references/` directory for detailed guidance that should be loaded only when needed.
- Optional `agents/openai.yaml` UI metadata. Its `default_prompt` must mention the exact `$skill-name`.

When adding or editing a skill, keep the SKILL.md as the single source of truth for how the skill
behaves; the landing page (`skills-landing.html`) is hand-maintained marketing copy that must be
updated separately if a skill's name or path changes.

Keep installable skill folders lean. Top-level entries under `skills/<name>/` should be limited to
`SKILL.md`, `scripts/`, `references/`, `agents/`, and intentional `assets/`; put demos, marketing
HTML, and presentation artifacts elsewhere.

## Installing in other projects

Copy folders from `skills/` into the target project's agent skills directory:

| Agent | Project path |
|---|---|
| Claude Code | `.claude/skills/` |
| Cursor | `.cursor/skills/` (also reads `.claude/skills/`) |
| Codex | `.codex/skills/` |

## git-bisect-ai helper

`scripts/bisect-run.sh` is the wrapper handed to `git bisect run`. Its contract — exit codes are
git bisect's verdict, not normal shell semantics:
- `0` → good (test passed)
- `125` → skip (commit can't be tested, e.g. won't build)
- `1`–`124`, `126` → bad
- `128`–`255` → abort the bisect

Flags: `--test "<cmd>"` (required), `--setup "<cmd>"`, `--timeout <secs>`,
`--setup-timeout <secs>`, `--log-dir <path>`, `--build-is-bug` (a failing setup means bad, not
skip — for hunting broken builds), `--invert` (a *passing* test is bad — for finding when a failing
test started passing), and `--allow-test-skip` (preserve test exit 125 as skip). It collapses other
nonzero test exits to plain `1` so the test command cannot accidentally abort the bisect.

The SKILL.md resolves the runner path at runtime via `find` under the repo root, so it works
regardless of whether the skill was installed under `skills/`, `.claude/skills/`, `.cursor/skills/`,
or `.codex/skills/`.

## Other helpers

- `semantic-commit-guard/scripts/install-hook.sh` installs a deterministic pre-commit gate for
  staged secrets, secret-like files, and oversized blobs. The full semantic architecture/docs review
  remains an agent task.
- `dependency-upgrade-loop/scripts/build-probe.sh` runs a build/test command with optional
  timeout, captures the full log, and highlights likely root-error lines for the upgrade loop.

## Validation and demos

Run `scripts/validate-skills.sh` before publishing or copying skills. It validates metadata,
installable skill folder shape, shell syntax, and smoke tests all bundled helper scripts in
temporary git repos.

The `demo-repos/` directory contains one resettable sandbox per skill. Each `setup.sh` materializes
the demo repo in place and prints the prompt to use with an agent.
