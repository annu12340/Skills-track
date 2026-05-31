# Rescue Receipt: semantic-commit-guard

- Created: 2026-05-31T000000Z
- Repo: demo-repos/commit-guard-demo
- Branch / commit reviewed: main @ HEAD, staged index
- Outcome: BLOCKED

## Commands Run
| Command | Purpose | Result |
|---|---|---|
| `git diff --cached --stat` | Confirm staged files exist. | `app/config.py`, `app/handlers.py`, and `README.md` staged. |
| `git rev-parse --show-toplevel` | Identify repo root. | `demo-repos/commit-guard-demo`. |
| `git diff --cached --name-status` | List staged paths. | Three modified files. |
| `git diff --cached -U0 --no-ext-diff` | Map findings to staged lines. | Exact added-line evidence collected. |
| `git show :app/config.py` | Inspect staged config blob without reading unstaged content. | Hardcoded credentials found. |

## Evidence Found
- Policy sources: `.semantic-guard.md`.
- Staged files reviewed: `app/config.py`, `app/handlers.py`, `README.md`.
- BLOCK `app/config.py`: hardcoded API key and DB password values were staged. Values redacted.
- BLOCK/WARN `app/handlers.py`: raw SQL and business logic moved into the thin handler layer, violating project policy.
- WARN `app/handlers.py`: debug print left on the request path.
- WARN `README.md`: docs claim no secrets are stored while staged source contains credentials.

## Files Changed
- `.repo-rescue/receipts/<timestamp>-semantic-commit-guard.md`

## Culprit / Root Cause
- A staged change bypassed environment-based secrets, moved service/database logic into the handler, and updated docs in a way that contradicts the code.

## Remaining Risk
- Only the staged index was reviewed. Unstaged local edits, generated files, and repository history were not scanned.
- Any real credential matching the staged values must be rotated even if the commit is abandoned.

## Recommended Next Action
- Move credentials back to environment variables, restore database access to `app/service.py`, remove debug output, update the README, and rotate any plausible live secret.
