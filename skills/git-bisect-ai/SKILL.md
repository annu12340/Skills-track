---
name: git-bisect-ai
description: >-
  Autonomously hunt down the exact commit that introduced a bug using an
  automated git bisect. Use when a user says a feature "broke" / "regressed" /
  "used to work" / "stopped working" and wants to find which commit caused it,
  or explicitly asks to bisect, find the offending/first-bad commit, or do
  regression archaeology. Drives `git bisect run` with a reproduction command
  (test suite, build, headless-browser check, or any custom command) and
  reports the culprit commit with its diff and an explanation of the cause.
---

# Git Bisect AI — The Autonomous Bug Hunter

Turn "this broke sometime last week" into "commit `a1b2c3d` broke it, here's
why." You act as a forensic QA engineer: pin down a good and a bad commit,
build a reliable reproduction, let `git bisect run` binary-search the history
unattended, then explain the offending change.

The whole technique lives or dies on one thing: **a reproduction command that
reliably exits 0 when the bug is absent and nonzero when it is present.** Get
that right and the rest is mechanical. Most of your effort goes here.

## Operating mode: auto, with checkpoints

Prefer the fully-automated `git bisect run <script>` path. But **stop and
confirm with the user twice**:

1. **Before starting** — confirm the good commit, the bad commit, and the exact
   reproduction command you'll use (after you've validated it, see Step 3).
2. **After it finishes** — present the culprit and the explanation; don't take
   follow-up actions (reverting, patching) unless asked.

Everything in between runs unattended.

---

## Workflow

### Step 0 — Safety check

Run these before touching anything; bisect rewrites the working tree.

- `git status --porcelain` — if the tree is dirty, **stop** and ask the user to
  commit or stash. Don't stash silently; you could lose their work.
- Record the starting point so you can always return to it:
  `git rev-parse --abbrev-ref HEAD` (branch name; may be `HEAD` if detached) and
  `git rev-parse HEAD` (the SHA). You will restore this in Step 6.
- Confirm you're in the right repo and it has history: `git log --oneline -1`.

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

### Step 3 — Validate the reproduction (do NOT skip)

Bisect is garbage-in, garbage-out. Prove the command discriminates **before**
running the search:

1. On the **bad** commit (current HEAD, or `git checkout <bad>`): run your
   `--test`. It MUST fail (nonzero).
2. On the **good** commit (`git checkout <good>`): run `--setup` then `--test`.
   It MUST pass (zero).
3. Return to start: `git checkout <original-ref>`.

If the bad commit passes or the good commit fails, your bounds or your repro are
wrong — fix them here, not after wasting a full bisect. Flaky result? Make the
test deterministic (pin seeds, add retries inside the script, increase
timeouts) or fall back to the manual loop in "When automation isn't enough."

### Step 4 — Checkpoint with the user

Before launching, show: the good SHA, the bad SHA, the commit count and
estimated steps, and the exact runner invocation. Get a yes.

### Step 5 — Run the automated bisect

Resolve the runner to the absolute path of `scripts/bisect-run.sh` in the
installed copy of this skill. Search under the repo root — the skill may live
at `skills/`, `.cursor/skills/`, `.claude/skills/`, or `.codex/skills/`:

```bash
git bisect start <bad> <good>
RUNNER="$(find "$(git rev-parse --show-toplevel)" -maxdepth 5 \
  -path '*/git-bisect-ai/scripts/bisect-run.sh' 2>/dev/null | head -1)"
git bisect run "$RUNNER" \
  --setup "<setup cmd or omit>" \
  --test  "<test cmd>" \
  --timeout 300        # optional; a hang counts as bad. Needs `timeout`/`gtimeout`
                       # (macOS: `brew install coreutils`); else runs untimed + warns.
  # --build-is-bug     # add when hunting a broken build
  # --invert           # add when the bug is that a test STARTED passing
```

If `find` returns nothing, ask the user where the skill is installed and pass
that path explicitly. Prefer an absolute path so checkouts during bisect do not
lose the runner.

The runner (see `scripts/bisect-run.sh`) maps exit codes to git's contract:
`0`=good, `125`=skip (e.g. a commit that won't build while you're hunting a
runtime bug), anything else=bad. git checks out the midpoint each round, runs
the wrapper, and narrows automatically until it prints
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
4. Offer next steps (don't auto-do them): show the fix, draft a revert
   (`git revert <sha>`), or write a regression test that locks the behavior.

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
