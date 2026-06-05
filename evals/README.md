# Evals — Repo Rescue Rangers

Golden-case test suite for all three skills. Each case specifies an input (staged
diff, scenario description, or manifest state) and the expected output
(verdict, findings, and reasoning checkpoints). Use these to verify that the AI
reasoning layer — the part that actually matters — behaves correctly.

## Structure

```
evals/
├── semantic-commit-guard/   # staged diff → BLOCK / WARN / PASS verdict
├── git-bisect-ai/           # bisect scenario → culprit commit + explanation
└── dependency-upgrade-loop/ # broken manifest → green build path
```

Each skill directory contains:
- `cases/` — one JSON file per test case (input + expected)
- `run.sh` — executes all cases and reports pass/fail

## Running

```bash
# Run all evals (requires ANTHROPIC_API_KEY in env)
bash evals/run-all.sh

# Run one skill's evals
bash evals/semantic-commit-guard/run.sh
bash evals/git-bisect-ai/run.sh
bash evals/dependency-upgrade-loop/run.sh

# Run a single case
bash evals/semantic-commit-guard/run.sh 001
```

## Case format

```json
{
  "id": "001",
  "description": "One-line summary of what this case tests.",
  "input": {
    "staged_diff": "...",          // for semantic-commit-guard
    "scenario": "...",             // for git-bisect-ai
    "manifest": "..."              // for dependency-upgrade-loop
  },
  "expected": {
    "verdict": "BLOCK",            // BLOCK | WARN | PASS
    "must_contain": ["api_key", "config.py:14"],  // strings response must include
    "must_not_contain": ["PASS"],  // strings response must NOT include
    "reasoning_checkpoints": [     // phrases demonstrating AI judgment, not just pattern match
      "high-entropy string",
      "rotate"
    ]
  }
}
```

## Pass criteria

A case passes when:
1. The verdict label matches (`BLOCK` / `WARN` / `PASS`).
2. Every `must_contain` string appears in the response (case-insensitive).
3. No `must_not_contain` string appears in the response.
4. At least one `reasoning_checkpoint` phrase appears (proves judgment, not pattern match).

## Current pass rates

Run `bash evals/run-all.sh --report` after each model change to update these.

| Skill | Cases | Target |
|---|---|---|
| semantic-commit-guard | 5 | 5/5 |
| git-bisect-ai | 5 | 5/5 |
| dependency-upgrade-loop | 5 | 5/5 |
