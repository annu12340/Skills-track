# demo-repos — one sandbox per skill

Three **independent** demo repos, one per skill in [`../skills/`](../skills/).
They're separate on purpose: each skill needs a *contradictory* starting state
(bisect wants a clean passing history, the guard wants a dirty staged diff,
the dependency upgrade loop wants a broken build), so cramming them into one
repo makes the demos fight each other.

Each demo is a folder with a single `setup.sh`. Running it **materializes a
throwaway git repo in place** with exactly the state that skill expects. Running
it again **resets** the demo from scratch. Only the `setup.sh` scripts are
tracked by the parent repo — the generated `.git`/source live only on disk.

| Demo | Skill it exercises | Starting state it creates |
|---|---|---|
| [`bisect-demo/`](bisect-demo/) | `git-bisect-ai` | ~8-commit history with a regression planted mid-way + a `v1.0` good tag |
| [`commit-guard-demo/`](commit-guard-demo/) | `semantic-commit-guard` | clean committed baseline + a **staged** diff that leaks a secret, lies in docs, and breaks the layering policy |
| [`dependency-upgrade-loop-demo/`](dependency-upgrade-loop-demo/) | `dependency-upgrade-loop` | a Python project pinned to ancient deps whose code won't build against modern versions |

## Run a demo

```bash
cd demo-repos/bisect-demo && bash setup.sh
```

Each `setup.sh` prints the exact prompt to give the agent and the manual
commands to drive the skill yourself. Re-run `bash setup.sh` any time to reset.

> The old `../test-repo/` and `../testing-repo/` were an earlier all-in-one
> attempt; these per-skill demos supersede them.
