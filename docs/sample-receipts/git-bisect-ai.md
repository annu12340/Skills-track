# Rescue Receipt: git-bisect-ai

- Created: 2026-05-31T000000Z
- Repo: demo-repos/bisect-demo
- Branch / starting commit: main @ HEAD
- Outcome: first bad commit found

## Commands Run
| Command | Purpose | Result |
|---|---|---|
| `git status --porcelain` | Confirm whether bisect can run in place. | Clean after demo setup. |
| `git rev-list --count v1.0..HEAD` | Estimate bisect range size. | 4 commits after `v1.0`. |
| `python3 -c "from mathlib.calc import multiply; import sys; sys.exit(0 if multiply(4,5)==20 else 1)"` | Validate the reproduction command. | Fails at `HEAD`, passes at `v1.0`. |
| `git bisect start HEAD v1.0` | Start the binary search. | Bisect initialized. |
| `git bisect run <runner> --test "<repro command>" --log-dir /tmp/git-bisect-ai-logs` | Search for the first bad commit. | Found the regression commit. |
| `git bisect reset` | Restore the original checkout. | Cleanup completed. |

## Evidence Found
- Range tested: `v1.0..HEAD`.
- Reproduction command: `multiply(4, 5)` must return `20`.
- Bisect result: the commit titled `Optimize multiply for readability`.
- Focused diff evidence: `multiply(a, b)` changed from multiplication to addition.

## Files Changed
- `.repo-rescue/receipts/<timestamp>-git-bisect-ai.md`

## Culprit Commit
- Commit: `<demo sha>`
- Author/date/message: Demo Author, 2026-05-27, `Optimize multiply for readability`
- Why it broke: `multiply(4, 5)` now returns `9` because the implementation returns `a + b` instead of `a * b`.

## Remaining Risk
- This demo uses a narrow deterministic repro, so coverage is limited to the `multiply` behavior.
- Historical commits outside the `v1.0..HEAD` range were not tested.

## Recommended Next Action
- Revert or fix the commit, then add a regression test that locks `multiply(4, 5) == 20`.
