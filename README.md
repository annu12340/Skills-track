# Repo Rescue Rangers

Three [Agent Skills](https://agentskills.io/) that cover the repo lifecycle — **prevent**, **diagnose**, **recover**.

| Skill | Role | Status |
|---|---|---|
| [git-bisect-ai](skills/git-bisect-ai/) | Find the exact commit that introduced a regression | Implemented (+ `scripts/bisect-run.sh`) |
| [semantic-git-hook-guard](skills/semantic-git-hook-guard/) | Block commits that violate security or architecture intent | Skeleton |
| [dependency-graveyard-resurrection](skills/dependency-graveyard-resurrection/) | Upgrade stale deps and rewrite code until the build passes | Skeleton |

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
cp -r skills/git-bisect-ai skills/semantic-git-hook-guard skills/dependency-graveyard-resurrection \
  YOUR_PROJECT/.cursor/skills/
```

No package manager or build step required. Restart the agent session if skills are not picked up automatically.

## Try the demos

The `test-repo/` directory is a separate git repo with planted bugs for each skill. From the repo root:

```bash
cd test-repo
cat DEMO.md
```
