---
name: git-bisect-ai
description: >-
  Find the first commit that introduced a regression with automated or manual
  `git bisect`. Use when a user says something broke, regressed, used to work,
  stopped working, or asks to find the offending/first-bad commit. Builds a
  reliable pass/fail reproduction, validates good and bad bounds, drives
  `git bisect run` with the bundled runner, preserves the user's worktree, and
  reports the culprit commit with focused diff analysis, cleanup, and a
  shareable Rescue Receipt.
---

# Git Bisect AI

Turn "this broke sometime last week" into "commit `a1b2c3d` broke it, here's
why." You act as a forensic QA engineer: pin down a good and a bad commit,
build a reliable reproduction, let `git bisect run` binary-search the history
unattended, then explain the offending change.

The whole technique lives or dies on one thing: **a reproduction command that
reliably exits 0 when the bug is absent and nonzero when it is present.** Get
that right and the rest is mechanical. Most of your effort goes here.

## Operating Contract

- Prefer fully automated `git bisect run` after the reproduction is validated.
- Preserve the user's worktree. If the current tree is dirty, prefer a temporary
  `git worktree` for the bisect instead of asking the user to stash unrelated
  work. Ask only when dirty files are needed by the reproduction and are not
  committed.
- Keep reproduction scripts outside the bisected checkout, e.g. under `/tmp`,
  and call them with absolute paths so historical checkouts cannot delete them.
- Never leave the repo mid-bisect. Always run `git bisect reset` in the bisect
  worktree, even on failure.
- Do not revert, patch, or commit after identifying the culprit unless asked.
- Before the final response, leave a Rescue Receipt at
  `.repo-rescue/receipts/<timestamp>-git-bisect-ai.md` unless the repo is
  read-only or the user asks for no artifacts. Keep it uncommitted unless asked.
- For browser repros, dirty-worktree patterns, setup command choices, and report
  templates, read `references/repro-patterns.md` only when that detail is needed.

## Battle Card

- **When to use it:** a behavior regressed, a test started failing, a build
  broke after some unknown commit, or the user asks for the first-bad/offending
  commit.
- **When not to use it:** there is no reproducible pass/fail signal, the
  suspected range has no known good point yet, the issue is caused by unstaged
  local edits, or the user wants a fix rather than provenance.
- **First command to run:** `git status --porcelain` to decide whether to work
  in place or create a temporary worktree.
- **Common failure modes:** bad/good bounds don't discriminate, flaky repro
  command, historical commits cannot build, runner path disappears during
  checkout, or the repo is left mid-bisect after an abort.
- **Good final answer includes:** first-bad SHA, author/date/message, tested
  range and reproduction command, focused diff explanation, cleanup status,
  Rescue Receipt path, remaining risk, and recommended next action.

## Workflow

### Step 0 — Safety check

Run these before touching anything:

- `git status --porcelain` to decide whether to bisect in-place or in a
  temporary worktree.
- Record the starting point:
  `git rev-parse --abbrev-ref HEAD` (branch name; may be `HEAD` if detached) and
  `git rev-parse HEAD` (the SHA).
- Confirm you're in the right repo and it has history: `git log --oneline -1`.
- Resolve the runner before checking out historical commits:

```bash
RUNNER="$(find "$(git rev-parse --show-toplevel)" -maxdepth 5 \
  -path '*/git-bisect-ai/scripts/bisect-run.sh' 2>/dev/null | head -1)"
```

If `RUNNER` is empty, search the known skill install roots or ask for the
installed skill path.

If the current tree is dirty and validation requires checking out old commits,
create a temporary worktree before Step 3 and run validation plus bisect there.
Do not ask the user to stash unrelated work.

### Step 1 — Define the bug and pick the bounds

You need three things. Ask only for what you can't infer.

- **What "broken" means.** A concrete, observable failure: a failing test, a
  build error, a 500, a button that does nothing. Vague reports ("it's slow")
  need sharpening into a pass/fail signal before bisect is possible.
- **A bad commit** — where the bug exists. Almost always `HEAD`. Verify in
  Step 3 that it actually reproduces.
- **A good commit** — where the feature worked. Translate the user's hint:
  - "last week" → `git rev-list -1 --before="7 days ago" HEAD`
  - "in the 1.2 release" → the tag: `v1.2`
  - "yesterday it was fine" → `git rev-list -1 --before="1 day ago" HEAD`
  - If they don't know, offer to walk back: test a commit ~N days/commits ago;
    if it's still bad, double N and retry until you find a good one (this is
    just manual exponential search for the lower bound).

Sanity-check the range size so the user knows the cost:
`git rev-list --count <good>..<bad>` → bisect needs about `log2(N)` steps.

### Step 2 — Choose the reproduction type

Map the failure to a `--test` command (and optional `--setup`) for the runner.
All four are just a shell command whose exit code is the verdict:

| Failure type | `--setup` (optional) | `--test` (exit 0 = good) |
|---|---|---|
| **Test suite** | install deps | run the specific test, e.g. `pytest tests/test_x.py::test_y -q`, `npm test -- -t "name"`, `go test ./pkg -run TestX` |
| **Build / compile** | — | the build, e.g. `make`, `npm run build`, `cargo build`. Pass `--build-is-bug`. |
| **Frontend / browser** | start dev server / install | a headless script that asserts the behavior and exits nonzero on failure (Playwright/Puppeteer node script, `playwright test`, etc.) |
| **Custom** | anything | any command the user gives whose exit code means good/bad |

Guidance:
- **Target the narrowest test** that captures the bug. A single test case
  bisects far faster and more reliably than the whole suite.
- **Don't have a test? Write one.** A throwaway repro script that exercises the
  broken path and `exit 1`s on failure is exactly what bisect needs. Keep it
  outside the bisected paths (e.g. `/tmp`) so checkouts don't clobber it, and
  reference it by absolute path.
- **Frontend:** the test command is a node/Playwright script that launches a
  headless browser, drives the page, and exits nonzero when the assertion
  fails. Make sure `--setup` (re)starts the dev server per commit if the build
  output changes between commits.
- **Flaky failure:** run the assertion multiple times inside the repro script
  and fail only on a deterministic signal. A flaky oracle produces a wrong
  culprit.

### Step 3 — Validate the reproduction (do NOT skip)

Bisect is garbage-in, garbage-out. Prove the command discriminates before
running the search:

1. In the selected workspace, on the **bad** commit (current HEAD, or
   `git checkout <bad>`): run your `--test`. It MUST fail (nonzero).
2. In that same workspace, on the **good** commit (`git checkout <good>`): run
   `--setup` then `--test`.
   It MUST pass (zero).
3. Return to the bad commit or original ref before starting bisect.

If the bad commit passes or the good commit fails, your bounds or your repro are
wrong — fix them here, not after wasting a full bisect. Flaky result? Make the
test deterministic (pin seeds, add retries inside the script, increase
timeouts) or fall back to the manual loop in "When automation isn't enough."

### Step 4 — Choose the bisect workspace

- If the current tree is clean, bisect in place and rely on `git bisect reset`.
- If the current tree is dirty or the user is actively working, create a
  disposable worktree at the bad commit:

```bash
WT="${TMPDIR:-/tmp}/git-bisect-ai-$(date +%s)"
git worktree add --detach "$WT" <bad>
cd "$WT"
```

Remove it after cleanup with `git worktree remove "$WT"` when possible.

Before launching, state the good SHA, bad SHA, commit count, estimated steps,
workspace, and exact runner invocation. If any bound or command is inferred with
low confidence, ask before continuing.

### Step 5 — Run the automated bisect

```bash
git bisect start <bad> <good>
git bisect run "$RUNNER" \
  --setup "<setup cmd or omit>" \
  --test  "<test cmd>" \
  --timeout 300 \
  --log-dir "${TMPDIR:-/tmp}/git-bisect-ai-logs"
```

Useful runner flags:
- `--setup-timeout <seconds>` to limit install/build setup separately.
- `--build-is-bug` when a failing setup/build is the regression, not a skipped
  untestable commit.
- `--invert` when the bug is that a test started passing.
- `--allow-test-skip` when the test command intentionally returns 125 for
  "cannot judge this commit."

The runner (see `scripts/bisect-run.sh`) maps exit codes to git's contract:
`0`=good, `125`=skip (e.g. a commit that won't build while you're hunting a
runtime bug), anything else=bad. Test command exit codes that could abort bisect
are collapsed to a plain bad verdict unless `--allow-test-skip` is set. git
checks out the midpoint each round, runs the wrapper, and narrows until it prints
**"`<sha>` is the first bad commit."**

If many commits in the range can't be built/tested, that's normal — they're
auto-skipped (125); git may report a small set of candidates instead of one.

### Step 6 — Report, then always clean up

1. Capture the result: `git bisect log` (full trail) and note the first-bad SHA.
2. **Always** run `git bisect reset` to end the bisect and restore HEAD, then
   verify you're back on the original ref from Step 0 (`git checkout <ref>` if
   not). Do this even if the bisect errored or you abort partway.
3. Present the culprit:
   - `git show --stat <sha>` and the focused diff: `git show <sha>`
   - Author, date, message, PR/ticket refs from the message.
   - **The explanation** — the point of the whole exercise: read the diff and
     state *why* this change introduced the failure (the specific line/logic),
     not just that it's the boundary commit.
4. Remove a disposable worktree if you created one.
5. Offer next steps (don't auto-do them): show the fix, draft a revert
   (`git revert <sha>`), or write a regression test that locks the behavior.
6. Create the Rescue Receipt. Include commands run, evidence found, files you
   changed, the culprit commit, remaining risk, and the recommended next action.
   Use the template in `references/repro-patterns.md` when you need the exact
   structure.

---

## Worked example (end to end)

A `multiply(a, b)` regression: it returns the wrong value, and a test asserts it.
The user says "math was fine in the v1.0 release."

```bash
# Step 0 — clean tree, record where we are
git status --porcelain          # empty: good
git rev-parse --abbrev-ref HEAD # main   (restore target)

# Step 1 — bounds. bad = HEAD, good = the v1.0 tag.
git rev-list --count v1.0..HEAD # 18 commits -> ~5 steps (log2 18)

# Step 3 — VALIDATE the repro discriminates, before bisecting
python -m pytest tests/test_maths.py::test_multiply -q   # on HEAD: FAILS (good — bug present)
git checkout v1.0
python -m pytest tests/test_maths.py::test_multiply -q   # PASSES (good — bug absent)
git checkout main

# Step 5 — run it unattended
git bisect start HEAD v1.0
RUNNER="$(find "$(git rev-parse --show-toplevel)" -maxdepth 5 \
  -path '*/git-bisect-ai/scripts/bisect-run.sh' 2>/dev/null | head -1)"
git bisect run "$RUNNER" \
  --test "python -m pytest tests/test_maths.py::test_multiply -q" \
  --log-dir "${TMPDIR:-/tmp}/git-bisect-ai-logs"
# -> "a1b2c3d is the first bad commit"

# Step 6 — ALWAYS clean up, then explain
git bisect reset
git show a1b2c3d        # read the diff: multiply() was changed to `return a + b`
```

Report: commit `a1b2c3d`, author/date/message, and the *why* — the operator was
changed from `*` to `+`, so `multiply` adds instead of multiplies.

---

## When automation isn't enough (manual loop)

Fall back to driving bisect by hand when the verdict needs judgment a script
can't give — intermittent failures, "it's subtly wrong" rather than a hard
fail, or a repro that needs interactive steps.

```bash
git bisect start
git bisect bad <bad>
git bisect good <good>
# git checks out a midpoint; you evaluate it yourself, then mark it:
git bisect good      # this commit is fine
git bisect bad       # this commit has the bug
git bisect skip      # can't tell / won't build — try a neighbor
# repeat until git names the first bad commit, then:
git bisect reset
```

Use `git bisect skip` for any commit you genuinely can't judge; don't guess —
a wrong mark sends the search down the wrong half and invalidates the result.

---

## Pitfalls

- **Dirty tree / untracked build artifacts.** Checkouts fail or leak state
  across commits. Ensure a clean tree (Step 0) and that `--setup` rebuilds
  deterministically each round.
- **Stale dependencies between commits.** If `package-lock`/`go.mod`/`Cargo.lock`
  changed across the range, reinstall in `--setup`, or commits will "fail" for
  the wrong reason.
- **The repro file gets checked out away.** Keep test scripts outside the repo
  (e.g. `$TMPDIR`) and reference them absolutely.
- **First-parent only.** For a messy merge history, `git bisect start
  --first-parent <bad> <good>` bisects only mainline commits.
- **Submodules.** Add `git submodule update --init` to `--setup` if the bug
  depends on submodule state.
- **The "good" commit isn't actually good.** Always validate (Step 3); a bad
  lower bound produces a confident-but-wrong answer.
- **Forgetting to reset.** Leaving a repo mid-bisect is confusing and traps the
  user in a detached state. `git bisect reset` is non-negotiable cleanup.
- **Uncommitted repro dependencies.** If the repro needs local edits, commit
  them to a temporary branch or move the repro outside the checkout; otherwise
  historical checkouts will not contain what the test expects.
