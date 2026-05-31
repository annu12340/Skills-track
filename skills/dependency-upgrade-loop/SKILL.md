---
name: dependency-upgrade-loop
description: >-
  Upgrade or repair stale dependency stacks by iterating manifest changes,
  installs, build/test failures, and targeted code migrations until the project
  is green. Use when the user asks to update dependencies, migrate across major
  versions, fix dependency or peer conflicts, revive an old repo that no longer
  builds, get "latest" package versions working, or move off deprecated package
  APIs. Uses package-manager metadata and official migration notes, preserves
  user work, and reports blocked upgrades, behavior changes, verification, and
  a shareable Rescue Receipt.
---

# Dependency Upgrade Loop

A major upgrade rarely fails in one place - bumping a framework cascades through
peer dependencies, renamed APIs, removed exports, and changed defaults. This
skill works that cascade methodically: establish a baseline, upgrade in the
smallest safe increments, and after every bump run the build, read the actual
error, fix exactly what broke, and rebuild - looping until green or until you
hit a genuine boundary worth reporting.

The discipline that makes this work: **one logical change per verify run.**
Sometimes a logical change is one package; sometimes it is a framework plus its
required peers. Keep each step small enough that the next failure has a clear
cause.

## Operating Contract

- Preserve the user's work. Start with `git status --porcelain`; if the tree is
  dirty, inventory the touched files and avoid overwriting them. Ask only when
  dirty files overlap the upgrade or rollback cannot be isolated.
- Do not commit, reset, remove lockfiles, or switch branches unless the user
  explicitly asked for that. Prefer recorded diffs and clear checkpoints.
- When the target is "latest", verify versions with the package manager,
  registry metadata, or official release notes. Do not rely on model memory.
- Read official migration notes before crossing a major version. Use community
  posts only to explain errors after the primary source is checked.
- Treat behavior changes as decisions, not syntax fixes. Surface changed
  defaults, removed features, dropped runtime support, and security-sensitive
  migrations.
- Before the final response, leave a Rescue Receipt at
  `.repo-rescue/receipts/<timestamp>-dependency-upgrade-loop.md` unless the repo
  is read-only or the user asks for no artifacts. Keep it uncommitted unless
  asked.
- For package-manager commands, resolver triage, and boundary-report examples,
  read `references/ecosystem-triage.md` only when that detail is needed.

## Battle Card

- **When to use it:** the user asks to update dependencies, cross major
  versions, fix dependency or peer conflicts, revive an old repo, or get a
  stale project building again.
- **When not to use it:** there is no manifest or verification command, the
  request is only to inspect outdated packages, the user wants a broad rewrite
  unrelated to dependencies, or the current dirty work overlaps files you must
  edit and cannot be isolated.
- **First command to run:** `git status --porcelain` to inventory user work
  before touching manifests, lockfiles, or source.
- **Common failure modes:** big-bang upgrades, lockfile drift, force flags hiding
  resolver problems, chasing cascade errors instead of the first root error,
  skipping official migration notes, or reporting green without a real verify
  signal.
- **Good final answer includes:** package old -> new table, code migrations,
  commands and final verification, boundary or culprit dependency, behavior
  changes, files changed, Rescue Receipt path, remaining risk, and recommended
  next action.

## Workflow

### Step 0 — Safety and baseline

You will be editing manifests and source; make it reversible and measurable.

- Record `git status --porcelain`, current branch/SHA, package manager, runtime
  versions, manifest files, and lockfiles.
- Identify the strongest verification command available: tests first, then
  build/compile, typecheck, lint/import check.
- Run the verify command once before changing dependencies. Record whether the
  project is already broken. If already broken, decide whether the first target
  is "restore the old stack" or "upgrade while fixing the current failure."
- If the task is broad or risky, suggest a branch/worktree. Create it only when
  the user has asked for branch management or approved it.

### Step 1 — Inventory the dependencies

Parse the manifest(s) and understand what you're moving:

- Node: `package.json` plus exactly one lockfile. Use that package manager
  (`npm`, `yarn`, or `pnpm`) consistently. Inspect `engines`, peer dependency
  warnings, and framework plugin constraints.
- Python: `requirements*.txt`, `pyproject.toml`, `poetry.lock`, or `Pipfile`.
  Track Python version constraints before bumping packages that dropped old
  interpreter support.
- Go: `go.mod`/`go.sum`; use `go list -m -u all` and `go get module@version`.
- Rust: `Cargo.toml`/`Cargo.lock`; use `cargo update -p name --precise version`
  for narrow changes when possible.
- Ruby: `Gemfile`/`Gemfile.lock`; use `bundle update gem --conservative`.
- Java/Kotlin: `pom.xml`, `build.gradle`, version catalogs, and plugin versions.

Build an ordered plan, safest first:
1. Patch/minor bumps (low risk) before majors.
2. The framework/runtime that everything else pegs to (e.g. React, Django,
   Node engine) - its major version dictates what its ecosystem can be.
3. Peer dependencies of that framework, to versions compatible with the target.
4. Everything else.

### Step 2 — Use the build probe

Use `scripts/build-probe.sh` to run the verification command with a saved log
and highlighted root-error candidates:

```bash
PROBE="/absolute/path/to/dependency-upgrade-loop/scripts/build-probe.sh"
"$PROBE" --cmd "<verify command>" --timeout 600 --log "${TMPDIR:-/tmp}/dep-upgrade.log"
```

Resolve the script from the installed skill path, not from a path that may be
changed by the project build. If the helper is unavailable, run the same command
directly and capture the full log yourself.

The verify command is the loop's pass/fail oracle. It must exit 0 when healthy
and nonzero when broken.

### Step 3 — The upgrade loop (one change per iteration)

For each item in the plan:

1. **Read the upgrade notes first.** Before bumping across a major version,
   check the changelog, migration guide, and release notes. Knowing
   `componentWillMount` -> `useEffect`, or `url()` -> `re_path()`, up front
   turns a blind loop into a targeted edit.
2. **Apply one bump.** Edit the manifest to the next target version and install
   with the project's package manager so the lockfile updates consistently.
3. **Build** with the probe. Keep the log path for analysis and final reporting.
4. **Read the failure.** Open the captured log. Identify the *first* root error
   (later errors are often cascades). Map it to a cause: removed export, renamed
   API, changed signature, peer-version conflict, dropped default.
5. **Fix exactly that.** Rewrite the affected code to the new API, or adjust the
   peer version. Prefer official codemods when available, then review their diff.
6. **Rebuild.** Repeat 3–5 until this item's build is green.
7. **Checkpoint in notes.** Record package old -> new, files changed, and the
   error cleared. Commit only if the user asked you to manage commits.

Loop guard: if the same root error survives 3 focused fix attempts, stop and
report it as a boundary. Do not thrash or hide it with broad ignores.

### Step 4 — Triage failures accurately

- `ERESOLVE`, peer conflict, Bundler conflict, or resolver backtracking: solve
  the version graph first. Do not bypass with `--legacy-peer-deps`, force flags,
  broad upper-bound removals, or transitive pins unless reported as temporary.
- Removed export/import/module: find the package's replacement API, update the
  smallest affected call sites, then rebuild.
- Type errors after a major bump: check whether the library changed public
  types or whether local code relied on an internal type.
- Runtime/test failures after compile passes: compare migration notes for new
  defaults, stricter parsing, async behavior, serialization, timezone, or auth
  changes.
- Native build failures: check runtime/OS/toolchain support before editing app
  code.

### Step 5 — Report

When the full plan is green (or you've hit a boundary):

- **What changed:** a table of `package: old -> new` and, per package, the code
  migrations made (file:area, old API -> new API).
- **Boundaries hit:** any package you couldn't move and *why* (no compatible
  version, breaking change needing a product decision, a transitive conflict).
  Give the user the decision, don't invent one.
- **Behavioral changes:** any fix that changed runtime behavior, not just
  syntax (changed defaults, removed features). These need human review.
- **Verification:** the final build/test command output proving green, and the
  branch/worktree used if any. Do not merge unprompted.
- **Rescue Receipt:** create
  `.repo-rescue/receipts/<timestamp>-dependency-upgrade-loop.md` with commands
  run, evidence found, files changed, dependency culprit or boundary, remaining
  risk, and the recommended next action. Use the template in
  `references/ecosystem-triage.md` when you need the exact structure.

## Pitfalls

- **Big-bang bumps.** Upgrading everything at once produces an unreadable wall of
  errors with no clear cause. One change per build is the whole method.
- **Fixing cascade errors first.** The 30th error is usually caused by the 1st.
  Always resolve the earliest root failure, then rebuild before reading more.
- **Lockfile drift.** Editing the manifest without regenerating the lockfile (or
  vice versa) installs versions you didn't intend. Always reinstall after a bump.
- **Silencing instead of fixing.** Pinning a transitive dep, adding `--legacy-peer-deps`,
  `# type: ignore`, or `@ts-nocheck` to make the build pass hides the breakage.
  Use only as an explicitly reported temporary boundary - never as the fix.
- **Skipping changelogs.** Guessing at a new API wastes loop iterations. Read the
  migration guide before a major bump.
- **No real verify signal.** "It compiles" isn't "it works." Prefer the test
  suite as the oracle when one exists; note when you could only verify a build.
- **Behavior changes slipping through unflagged.** A syntactic migration can
  change semantics (new defaults, stricter parsing). Flag these explicitly.
