# Dependency Ecosystem Triage

Use this reference when the upgrade failure is package-manager specific, resolver-specific, or requires ecosystem commands beyond the core loop in `SKILL.md`.

## Package Manager Commands

Node:
- Detect manager from lockfile: `package-lock.json` -> npm, `pnpm-lock.yaml` -> pnpm, `yarn.lock` -> yarn.
- Inspect current/latest: `npm outdated`, `npm view <pkg> version peerDependencies engines`, `pnpm outdated`, `yarn outdated`.
- Narrow updates: `npm install <pkg>@<version>`, `pnpm up <pkg>@<version>`, `yarn add <pkg>@<version>`.
- Prefer fixing peer ranges over `--force` or `--legacy-peer-deps`.

Python:
- Detect manager from `pyproject.toml`, `poetry.lock`, `Pipfile.lock`, or requirements files.
- Inspect constraints: `python -m pip index versions <pkg>`, `poetry show --outdated`, `pip list --outdated`.
- Narrow updates: edit the constraint, then run the project manager install command.
- Check interpreter support before bumping packages that recently dropped old Python versions.

Go:
- Inspect updates: `go list -m -u all`.
- Narrow update: `go get module@version`, then `go mod tidy`.
- Treat module path changes as API migrations, not simple version bumps.

Rust:
- Inspect updates: `cargo update --dry-run`, `cargo tree -d`; use `cargo outdated` only if installed.
- Narrow update: `cargo update -p name --precise version`.
- Check feature flags when compile failures appear after resolver changes.

Ruby:
- Inspect updates: `bundle outdated`.
- Conservative update: `bundle update gem --conservative`.
- Check Ruby version constraints before changing framework majors.

Java/Kotlin:
- Inspect plugin and dependency versions in `pom.xml`, `build.gradle`, `gradle/libs.versions.toml`.
- Keep build-tool/plugin upgrades separate from runtime library upgrades when possible.

## Resolver Failure Triage

Classify the first root error before editing:
- Peer conflict or version solver failure: adjust the dependency graph first.
- Removed export or renamed import: read migration notes and update call sites.
- Type-only failure: check public type changes before weakening local types.
- Native extension failure: check runtime, OS, compiler, and package binary support.
- Runtime/test failure after compile passes: search migration notes for changed defaults.

Do not hide resolver failures with force flags, broad transitive pins, ignored type errors, or disabled tests unless the final report calls it out as a temporary boundary.

## Boundary Report Template

Use this format when an upgrade cannot be completed safely:

```text
Boundary: <package> <old> -> <target>
Observed failure: <first root error and log path>
Why it blocks: <no compatible peer / runtime dropped / product decision needed>
Options:
1. <recommended path>
2. <alternate path and tradeoff>
Verified state: <last passing command or current failing command>
```

## Rescue Receipt Template

Create this Markdown file under `.repo-rescue/receipts/` before the final
response. Use a UTC timestamp in the filename, for example
`2026-05-31T143012Z-dependency-upgrade-loop.md`.

```markdown
# Rescue Receipt: dependency-upgrade-loop

- Created: <UTC timestamp>
- Repo: <repo root or remote>
- Branch / starting commit: <branch> @ <sha>
- Outcome: <GREEN | BOUNDARY | PARTIAL UPGRADE | ABORTED>

## Commands Run
| Command | Purpose | Result |
|---|---|---|
| `<command>` | <install/build/test/inspect reason> | <pass/fail/log path> |

## Evidence Found
- Baseline verification: <command and result>.
- Upgrade notes checked: <official docs/changelogs>.
- Root errors cleared: <first error, cause, fix>.
- Final verification: <command, result, log path>.

## Files Changed
- <manifest/lock/source/test/doc files changed and why>

## Culprit Dependency / Boundary
- <package old -> new, peer conflict, removed API, dropped runtime, or "None; planned upgrade completed".>

## Remaining Risk
- <behavior changes, limited verification, runtime support, skipped packages, temporary pins, etc.>

## Recommended Next Action
- <review behavior change, run broader tests, deploy behind flag, decide boundary, or merge>
```
