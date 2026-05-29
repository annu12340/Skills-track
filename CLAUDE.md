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
| `skills/semantic-git-hook-guard/` | Pre-commit gate that judges the *meaning* of staged changes | **Skeleton** (SKILL.md describes behavior; no scripts yet) |
| `skills/dependency-graveyard-resurrection/` | Iteratively upgrade dependencies and rewrite code until the build passes | **Skeleton** (SKILL.md describes behavior; no scripts yet) |

Note the folder name and the skill `name:` in frontmatter can differ — e.g. the folder
`semantic-git-hook-guard/` defines `name: semantic-commit-guard`, and
`dependency-graveyard-resurrection/` defines `name: dependency-resurrection-engine`.

## Skill structure conventions

Each skill is a folder under `skills/` containing:
- A `SKILL.md` with YAML frontmatter (`name`, `description`) followed by the skill's instructions.
  The `description` is the trigger text the agent uses to decide when to invoke the skill — write it
  as "Use when the user…" with concrete trigger phrases.
- An optional `scripts/` directory for executable helpers the skill drives.

When adding or editing a skill, keep the SKILL.md as the single source of truth for how the skill
behaves; the landing page (`skills-landing.html`) is hand-maintained marketing copy that must be
updated separately if a skill's name or path changes.

## Installing in other projects

Copy folders from `skills/` into the target project's agent skills directory:

| Agent | Project path |
|---|---|
| Claude Code | `.claude/skills/` |
| Cursor | `.cursor/skills/` (also reads `.claude/skills/`) |
| Codex | `.codex/skills/` |

## git-bisect-ai: the one piece with real code

`scripts/bisect-run.sh` is the wrapper handed to `git bisect run`. Its contract — exit codes are
git bisect's verdict, not normal shell semantics:
- `0` → good (test passed)
- `125` → skip (commit can't be tested, e.g. won't build)
- `1`–`124`, `126` → bad
- `128`–`255` → abort the bisect

Flags: `--test "<cmd>"` (required), `--setup "<cmd>"`, `--timeout <secs>`, `--build-is-bug`
(a failing setup means bad, not skip — for hunting broken builds), `--invert` (a *passing* test
is bad — for finding when a failing test started passing). It collapses any nonzero test exit to
plain `1` so the test command can never accidentally trigger skip/abort.

The SKILL.md resolves the runner path at runtime via `find` under the repo root, so it works
regardless of whether the skill was installed under `skills/`, `.claude/skills/`, `.cursor/skills/`,
or `.codex/skills/`.

## Testing the bisect skill

There is no automated test suite. The `testing-repo/` and `test-repo/` directories are scratch
fixtures for exercising git-bisect-ai by hand. `testing-repo/maths.py` contains a deliberately
planted bug (`multiply` returns `a + b`) to act as a reproducible regression target.
